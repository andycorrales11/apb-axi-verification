// Passive. Channels handshake independently, so accepted requests are staged
// and a transaction is emitted only on the matching B or R beat. The staging
// queues double as a protocol check.

class axi_lite_monitor extends uvm_monitor;

  `uvm_component_utils(axi_lite_monitor)

  virtual axi_lite_if vif;

  uvm_analysis_port #(axi_lite_seq_item) ap;

  axi_lite_seq_item wr_q[$];
  axi_lite_seq_item rd_q[$];

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
    axi_lite_seq_item tr;

    `uvm_info(get_type_name(), "Starting run phase", UVM_LOW)
    forever begin
      @(posedge vif.ACLK);

      if (!vif.ARESETn) begin
        wr_q.delete();
        rd_q.delete();
        continue;
      end

      // Requests before responses: for a zero-strobe or out-of-map write the
      // bridge answers straight out of Setup (axi_lite_to_apb.sv:317-324), so
      // AWREADY and BVALID can be high in the same cycle.
      if (vif.AWVALID && vif.AWREADY && vif.WVALID && vif.WREADY) begin
        tr            = axi_lite_seq_item::type_id::create("tr");
        tr.dir        = AXI_WRITE;
        tr.addr       = vif.AWADDR;
        tr.prot       = vif.AWPROT;
        tr.data       = vif.WDATA;
        tr.strb       = vif.WSTRB;
        tr.addr_class = axi_lite_seq_item::classify_addr(vif.AWADDR);
        wr_q.push_back(tr);
      end

      if (vif.ARVALID && vif.ARREADY) begin
        tr            = axi_lite_seq_item::type_id::create("tr");
        tr.dir        = AXI_READ;
        tr.addr       = vif.ARADDR;
        tr.prot       = vif.ARPROT;
        tr.strb       = '0;
        tr.addr_class = axi_lite_seq_item::classify_addr(vif.ARADDR);
        rd_q.push_back(tr);
      end

      if (vif.BVALID && vif.BREADY) begin
        if (wr_q.size() == 0) begin
          `uvm_error(get_type_name(),
                     $sformatf("B beat with no outstanding write (BRESP=%s)",
                               axi_lite_seq_item::resp_name(vif.BRESP)))
        end else begin
          tr      = wr_q.pop_front();
          tr.resp = vif.BRESP;
          ap.write(tr);
        end
      end

      if (vif.RVALID && vif.RREADY) begin
        if (rd_q.size() == 0) begin
          `uvm_error(get_type_name(),
                     $sformatf("R beat with no outstanding read (RDATA=0x%0h RRESP=%s)",
                               vif.RDATA, axi_lite_seq_item::resp_name(vif.RRESP)))
        end else begin
          tr       = rd_q.pop_front();
          tr.rdata = vif.RDATA;
          tr.resp  = vif.RRESP;
          ap.write(tr);
        end
      end
    end
  endtask

  // Still staged at the end = accepted but never answered.
  virtual function void check_phase(uvm_phase phase);
    if (wr_q.size() != 0)
      `uvm_error(get_type_name(),
                 $sformatf("%0d write request(s) accepted but never answered on B", wr_q.size()))
    if (rd_q.size() != 0)
      `uvm_error(get_type_name(),
                 $sformatf("%0d read request(s) accepted but never answered on R", rd_q.size()))
  endfunction

endclass : axi_lite_monitor
