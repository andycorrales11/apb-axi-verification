// AXI agent ACTIVE on the front of the bridge; the Week-1 APB agent reused
// PASSIVE on the bus behind it.

class axi_env extends uvm_env;

  axi_lite_agent      axi_agent;
  apb_agent           apb_agnt;
  axi_lite_scoreboard sb;
  axi_lite_coverage   cov;

  `uvm_component_utils(axi_env)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // Set before create so apb_agent's build_phase sees it.
    uvm_config_db#(uvm_active_passive_enum)::set(this, "apb_agnt", "is_active", UVM_PASSIVE);

    axi_agent = axi_lite_agent::type_id::create("axi_agent", this);
    apb_agnt  = apb_agent::type_id::create("apb_agnt", this);
    sb        = axi_lite_scoreboard::type_id::create("sb", this);
    cov       = axi_lite_coverage::type_id::create("cov", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    axi_agent.mon.ap.connect(sb.axi_imp);
    apb_agnt.mon.ap.connect(sb.apb_imp);
    axi_agent.drv.ap.connect(cov.analysis_export);
  endfunction

endclass : axi_env
