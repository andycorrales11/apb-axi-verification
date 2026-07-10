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
    vif.PSEL <= 0;
    vif.PENABLE <= 0;
    @(posedge vif.PRESETn);  // wait for reset deassertion
    forever begin
      seq_item_port.get_next_item(req);
      send_to_dut(req);
      seq_item_port.item_done();
    end
  endtask

  virtual task send_to_dut(apb_seq_item req);
    // SETUP phase (one clock)
    vif.PSEL    <= 1;
    vif.PENABLE <= 0;
    vif.PADDR   <= req.addr;
    vif.PWRITE  <= (req.dir == WRITE);
    vif.PPROT   <= req.PPROT;
    vif.PWDATA  <= req.data;
    vif.PSTRB   <= req.PSTRB;
    @(vif);

    // ACCESS phase: hold PENABLE high until the slave samples ready,
    vif.PENABLE <= 1;
    do
      @(vif);
    while (!vif.PREADY);

    if (req.dir == READ) begin
      req.rdata  = vif.PRDATA;
      req.slverr = vif.PSLVERR;
    end

    vif.PSEL    <= 0;
    vif.PENABLE <= 0;
  endtask

endclass : apb_driver
