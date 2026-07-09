class apb_env extends uvm_env;

  apb_agent      agent;
  apb_scoreboard sb;
  apb_coverage   cov;

  `uvm_component_utils(apb_env)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = apb_agent::type_id::create("agent", this);
    sb    = apb_scoreboard::type_id::create("sb", this);
    cov   = apb_coverage::type_id::create("cov", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    agent.mon.ap.connect(sb.ap_imp);
    agent.mon.ap.connect(cov.analysis_export);
  endfunction

endclass : apb_env
