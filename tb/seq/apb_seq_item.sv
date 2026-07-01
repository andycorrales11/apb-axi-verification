typedef enum { READ, WRITE } apb_dir_e;

class apb_seq_item extends uvm_sequence_item;
  `uvm_object_utils(apb_seq_item)

  rand logic [APB_ADDR_WIDTH-1:0] addr;
  rand logic [APB_DATA_WIDTH-1:0] data;
  rand apb_dir_e dir;
  rand logic [APB_DATA_WIDTH/8-1:0] PSTRB;
  rand logic [2:0] PPROT;
  logic [APB_DATA_WIDTH-1:0] rdata;
  logic slverr;

  function new(string name = "apb_seq_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("APB transaction: addr=0x%0h, data=0x%0h, dir=%s, PSTRB=0x%0h, PPROT=0x%01h, rdata=0x%0h, slverr=%b",
                     addr, data, (dir == READ) ? "READ" : "WRITE", PSTRB, PPROT, rdata, slverr);
  endfunction

  // TODO: add constraints and field automation.

endclass : apb_seq_item
