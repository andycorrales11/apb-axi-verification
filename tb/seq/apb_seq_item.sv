// One APB read or write, at the abstraction the driver consumes and the monitor
// produces. This is the contract between stimulus, checker, and coverage -- get
// the fields right and the rest gets easier.

typedef enum { READ, WRITE } apb_dir_e;

class apb_seq_item extends uvm_sequence_item;
  `uvm_object_utils(apb_seq_item)

  // Stimulus-shaping knob: when set, addr lands outside the decoded register
  // range so the slave must flag PSLVERR. ~10% of random transfers.
  rand bit force_decode_err;

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

  // Word-aligned always: the RTL decodes PADDR[5:2] and the scoreboard keys
  // its reference memory on the full address, so unaligned addresses would
  // silently alias in the DUT but not in the model.
  constraint c_addr_aligned {addr[1:0] == 2'b00;}

  // 50/50 split of error addresses between just-past-the-boundary and far
  // out-of-range. A plain `inside` over the union would let the solver pick
  // uniformly over ~2^31 values, so the 16 boundary addresses (which catch
  // decode off-by-one bugs) would almost never be generated.
  rand bit err_near_boundary;

  constraint c_addr_range {
    if (force_decode_err) {
      if (err_near_boundary) addr inside {[32'h40 : 32'h7C]};
      else addr inside {[32'h8000_0000 : 32'hFFFF_FF00]};
    } else {
      addr inside {[32'h0 : 32'h3C]};
    }
  }

  constraint c_decode_err_dist {force_decode_err dist {0 := 9, 1 := 1};}

endclass : apb_seq_item
