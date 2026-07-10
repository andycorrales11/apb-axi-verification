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
      `uvm_fatal(get_type_name(), "Virtual interface must be set for: " + get_full_name())
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
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.PSEL && !vif.mon_cb.PENABLE) begin
        // SETUP edge
        addr  = vif.mon_cb.PADDR;
        dir   = vif.mon_cb.PWRITE ? WRITE : READ;
        wdata = vif.mon_cb.PWDATA;
        strb  = vif.mon_cb.PSTRB;
        prot  = vif.mon_cb.PPROT;

        // Wait for the completing edge: ACCESS phase with PREADY high.
        do
          @(vif.mon_cb);
        while (!(vif.mon_cb.PENABLE && vif.mon_cb.PREADY));

        tr = apb_seq_item::type_id::create("tr");
        tr.addr  = addr;
        tr.dir   = dir;
        tr.PSTRB = strb;
        tr.PPROT = prot;
        if (dir == WRITE) tr.data = wdata;
        else tr.rdata = vif.mon_cb.PRDATA;
        tr.slverr = vif.mon_cb.PSLVERR;
        ap.write(tr);
      end
    end
  endtask
endclass : apb_monitor
