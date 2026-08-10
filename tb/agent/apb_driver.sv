class apb_driver extends uvm_driver #(apb_seq_item);

  virtual apb_if vif;

  `uvm_component_utils(apb_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal(get_type_name(), {"Virtual interface must be set for: ", get_full_name()})
    end
  endfunction

  // NOTE: this driver synchronizes on @(posedge vif.PCLK) and drives the raw
  // interface signals with nonblocking assignments instead of going through
  // vif.mst_cb. Verilator 5.048's clocking-block scheduling proved unreliable
  // here: @(mst_cb) can fire twice in one timestep at the reset edge, and
  // output drives issued a cycle apart were applied in the same cycle,
  // collapsing the SETUP phase. NBA writes at the clock edge give the same
  // race-free semantics (DUT samples them one edge later).
  virtual task run_phase(uvm_phase phase);
    `uvm_info(get_type_name(), "Starting run_phase", UVM_LOW)
    vif.PSEL    <= 0;
    vif.PENABLE <= 0;
    @(posedge vif.PRESETn);  // wait for reset deassertion
    forever begin
      seq_item_port.get_next_item(req);
      send_to_dut(req);
      seq_item_port.item_done();
    end
  endtask

  virtual task send_to_dut(apb_seq_item req);
    // SETUP phase: drives land at the end of this timestep, the DUT samples
    // them at the next posedge.
    vif.PSEL    <= 1;
    vif.PENABLE <= 0;
    vif.PADDR   <= req.addr;
    vif.PWRITE  <= (req.dir == WRITE);
    vif.PPROT   <= req.PPROT;
    vif.PWDATA  <= req.data;
    vif.PSTRB   <= req.PSTRB;
    @(posedge vif.PCLK);  // DUT samples SETUP here

    // ACCESS phase: hold PENABLE high until the slave reports ready. Raw
    // reads at the edge see pre-edge values -- the same view the DUT has.
    vif.PENABLE <= 1;
    do
      @(posedge vif.PCLK);
    while (!vif.PREADY);

    if (req.dir == READ) begin
      req.rdata  = vif.PRDATA;
    end
    req.slverr = vif.PSLVERR;

    vif.PSEL    <= 0;
    vif.PENABLE <= 0;
  endtask

endclass : apb_driver
