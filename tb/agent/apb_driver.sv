class apb_driver extends uvm_driver #(apb_seq_item);

  virtual apb_if vif;

  `uvm_component_utils(apb_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal(get_type_name(), "Virtual interface must be set for: " + get_full_name())
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    `uvm_info(get_type_name(), "Starting run_phase", UVM_LOW)
    vif.mst_cb.PSEL <= 0;
    vif.mst_cb.PENABLE <= 0;
    @(posedge vif.PRESETn);  // wait for reset deassertion
    forever begin
      seq_item_port.get_next_item(req);
      send_to_dut(req);
      seq_item_port.item_done();
    end
  endtask

  virtual task send_to_dut(apb_seq_item req);
    // SETUP phase (one clock)
    vif.mst_cb.PSEL    <= 1;
    vif.mst_cb.PENABLE <= 0;
    vif.mst_cb.PADDR   <= req.addr;
    vif.mst_cb.PWRITE  <= (req.dir == WRITE);
    vif.mst_cb.PPROT   <= req.PPROT;
    vif.mst_cb.PWDATA  <= req.data;
    vif.mst_cb.PSTRB   <= req.PSTRB;
    @(vif.mst_cb);

    // ACCESS phase: hold PENABLE high until the slave samples ready,
    vif.mst_cb.PENABLE <= 1;
    do
      @(vif.mst_cb);
    while (!vif.mst_cb.PREADY);

    if (req.dir == READ) begin
      req.rdata  = vif.mst_cb.PRDATA;
      req.slverr = vif.mst_cb.PSLVERR;
    end

    vif.mst_cb.PSEL    <= 0;
    vif.mst_cb.PENABLE <= 0;
  endtask

endclass : apb_driver
