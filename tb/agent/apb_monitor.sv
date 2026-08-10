class apb_monitor extends uvm_monitor;
  `uvm_component_utils(apb_monitor)

  virtual apb_if vif;

  uvm_analysis_port #(apb_seq_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal(get_type_name(), {"Virtual interface must be set for: ", get_full_name()})
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    logic [APB_ADDR_WIDTH-1:0]   addr;
    apb_dir_e                    dir;
    logic [APB_DATA_WIDTH-1:0]   wdata;
    logic [APB_DATA_WIDTH/8-1:0] strb;
    logic [                 2:0] prot;
    apb_seq_item                 tr;

    `uvm_info(get_type_name(), "Starting run phase", UVM_LOW)
    // Samples raw interface signals at @(posedge vif.PCLK) instead of using
    // vif.mon_cb -- see the note in apb_driver.sv about Verilator 5.048's
    // clocking-block scheduling. Raw reads at the edge see pre-edge values,
    // i.e. exactly what the DUT's flops sample.
    forever begin
      @(posedge vif.PCLK);
      if (vif.PSEL && !vif.PENABLE) begin
        // SETUP edge
        addr  = vif.PADDR;
        dir   = vif.PWRITE ? WRITE : READ;
        wdata = vif.PWDATA;
        strb  = vif.PSTRB;
        prot  = vif.PPROT;

        // Wait for the completing edge: ACCESS phase with PREADY high.
        do
          @(posedge vif.PCLK);
        while (!(vif.PENABLE && vif.PREADY));

        tr = apb_seq_item::type_id::create("tr");
        tr.addr  = addr;
        tr.dir   = dir;
        tr.PSTRB = strb;
        tr.PPROT = prot;
        if (dir == WRITE) tr.data = wdata;
        else tr.rdata = vif.PRDATA;
        tr.slverr = vif.PSLVERR;
        ap.write(tr);
      end
    end
  endtask
endclass : apb_monitor
