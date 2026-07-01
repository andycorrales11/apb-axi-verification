class apb_driver extends uvm_driver #(apb_seq_item);

  virtual apb_if vif;

  `uvm_component_utils(apb_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // TODO: build_phase -> get vif from config_db.
  // TODO: run_phase   -> reset, then get_next_item/drive/item_done loop.
  // TODO: task drive_transfer(apb_seq_item tr);

endclass : apb_driver
