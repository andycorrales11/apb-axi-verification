// Drives the five AXI4-Lite channels as the master. Raw signals + NBA on
// @(posedge ACLK), not the clocking blocks -- see the NOTE in apb_driver.sv.
//
// Bridge facts this depends on (axi_lite_to_apb.sv:129-132): the write request
// needs AWVALID and WVALID both high, and AWREADY/WREADY are the same
// expression, so AW and W always handshake together -- aw_w_skew stalls the
// leader, it does not split the handshake. READY is combinational on VALID, so
// VALID never waits on READY.
//
// Mid-test reset is not handled, same gap as apb_driver.

class axi_lite_driver extends uvm_driver #(axi_lite_seq_item);

  virtual axi_lite_if vif;

  // Coverage subscribes here, not to the monitor: only the driver knows the
  // timing it chose.
  uvm_analysis_port #(axi_lite_seq_item) ap;

  `uvm_component_utils(axi_lite_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual axi_lite_if)::get(this, "", "axi_vif", vif)) begin
      `uvm_fatal(get_type_name(), {"Virtual interface must be set for: ", get_full_name()})
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    `uvm_info(get_type_name(), "Starting run_phase", UVM_LOW)
    reset_signals();
    @(posedge vif.ARESETn);
    forever begin
      seq_item_port.get_next_item(req);
      drive(req);
      ap.write(req);  // after the response, so coverage can bin resp too
      seq_item_port.item_done();
    end
  endtask

  virtual task reset_signals();
    vif.AWADDR  <= '0;
    vif.AWPROT  <= '0;
    vif.AWVALID <= 1'b0;
    vif.WDATA   <= '0;
    vif.WSTRB   <= '0;
    vif.WVALID  <= 1'b0;
    vif.BREADY  <= 1'b0;
    vif.ARADDR  <= '0;
    vif.ARPROT  <= '0;
    vif.ARVALID <= 1'b0;
    vif.RREADY  <= 1'b0;
  endtask

  virtual task drive(axi_lite_seq_item req);
    if (req.dir == AXI_WRITE) drive_write(req);
    else drive_read(req);
  endtask

  virtual task drive_write(axi_lite_seq_item req);
    fork
      drive_aw(req);
      drive_w(req);
    join
    collect_b(req);
  endtask

  // VALID drops on the same edge the handshake is seen; one cycle late and the
  // bridge accepts the request twice.
  virtual task drive_aw(axi_lite_seq_item req);
    if (req.aw_w_skew == W_FIRST) repeat (req.skew_cycles) @(posedge vif.ACLK);
    vif.AWADDR  <= req.addr;
    vif.AWPROT  <= req.prot;
    vif.AWVALID <= 1'b1;
    do
      @(posedge vif.ACLK);
    while (!(vif.AWVALID && vif.AWREADY));
    vif.AWVALID <= 1'b0;
  endtask

  virtual task drive_w(axi_lite_seq_item req);
    if (req.aw_w_skew == AW_FIRST) repeat (req.skew_cycles) @(posedge vif.ACLK);
    vif.WDATA  <= req.data;
    vif.WSTRB  <= req.strb;
    vif.WVALID <= 1'b1;
    do
      @(posedge vif.ACLK);
    while (!(vif.WVALID && vif.WREADY));
    vif.WVALID <= 1'b0;
  endtask

  // Withholding BREADY is real backpressure: a full write-response register
  // stalls the bridge's APB FSM (axi_lite_to_apb.sv:298).
  virtual task collect_b(axi_lite_seq_item req);
    repeat (req.b_ready_delay) @(posedge vif.ACLK);
    vif.BREADY <= 1'b1;
    do
      @(posedge vif.ACLK);
    while (!(vif.BVALID && vif.BREADY));
    req.resp   = vif.BRESP;
    vif.BREADY <= 1'b0;
  endtask

  virtual task drive_read(axi_lite_seq_item req);
    vif.ARADDR  <= req.addr;
    vif.ARPROT  <= req.prot;
    vif.ARVALID <= 1'b1;
    do
      @(posedge vif.ACLK);
    while (!(vif.ARVALID && vif.ARREADY));
    vif.ARVALID <= 1'b0;

    repeat (req.r_ready_delay) @(posedge vif.ACLK);
    vif.RREADY <= 1'b1;
    do
      @(posedge vif.ACLK);
    while (!(vif.RVALID && vif.RREADY));
    req.rdata  = vif.RDATA;
    req.resp   = vif.RRESP;
    vif.RREADY <= 1'b0;
  endtask

endclass : axi_lite_driver
