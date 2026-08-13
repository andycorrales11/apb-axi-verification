// One AXI4-Lite read or write, plus the master-side timing choices.

// AXI_-prefixed: apb_uvm_pkg is imported and already has READ/WRITE in scope.
typedef enum {
  AXI_READ,
  AXI_WRITE
} axi_dir_e;

typedef enum {
  ADDR_REG,     // 0x00-0x3F  -> slave register, expect OKAY
  ADDR_SLVERR,  // 0x40-0xFF  -> mapped, but past the slave's 16 regs
  ADDR_DECERR   // >= 0x100   -> outside the bridge's map
} axi_addr_class_e;

typedef enum {
  AW_FIRST,
  W_FIRST,
  SAME_CYCLE
} axi_skew_e;

class axi_lite_seq_item extends uvm_sequence_item;

  `uvm_object_utils(axi_lite_seq_item)

  // ---- request ----
  rand axi_dir_e                    dir;
  rand logic [AXI_ADDR_WIDTH-1:0]   addr;
  rand logic [AXI_DATA_WIDTH-1:0]   data;
  rand logic [AXI_DATA_WIDTH/8-1:0] strb;
  rand logic [2:0]                  prot;

  // ---- master-side timing ----
  rand axi_skew_e   aw_w_skew;
  rand int unsigned skew_cycles;
  rand int unsigned b_ready_delay;
  rand int unsigned r_ready_delay;

  // ---- stimulus shaping ----
  rand axi_addr_class_e addr_class;
  rand bit              err_near_boundary;

  // ---- results: filled by the driver/monitor, NOT randomized ----
  logic [AXI_DATA_WIDTH-1:0] rdata;
  logic [1:0]                resp;

  function new(string name = "axi_lite_seq_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf(
        "AXI4-Lite %s: addr=0x%0h (%s) data=0x%0h strb=0x%0h prot=0x%01h -> rdata=0x%0h resp=%s",
        (dir == AXI_READ) ? "READ " : "WRITE", addr, addr_class.name(), data, strb, prot,
        rdata, resp_name(resp));
  endfunction

  // For the monitor and coverage, which only see wires. The scoreboard must NOT
  // call this -- it restates the boundaries itself.
  static function axi_addr_class_e classify_addr(logic [AXI_ADDR_WIDTH-1:0] a);
    if (a >= 32'h0000_0100) return ADDR_DECERR;
    else if (a >= 32'h0000_0040) return ADDR_SLVERR;
    else return ADDR_REG;
  endfunction

  static function string resp_name(logic [1:0] r);
    case (r)
      2'b00:   return "OKAY";
      2'b01:   return "EXOKAY";
      2'b10:   return "SLVERR";
      default: return "DECERR";
    endcase
  endfunction

  // Keeps the AXI address and the APB address the bridge derives from it
  // identical, so the cross-check can compare them directly.
  constraint c_addr_aligned {addr[1:0] == 2'b00;}

  constraint c_addr_class_dist {
    addr_class dist {ADDR_REG := 7, ADDR_SLVERR := 2, ADDR_DECERR := 2};
  }

  constraint c_addr_range {
    if (addr_class == ADDR_REG) {
      addr inside {[32'h0000_0000 : 32'h0000_003C]};
    } else if (addr_class == ADDR_SLVERR) {
      addr inside {[32'h0000_0040 : 32'h0000_00FC]};
    } else {
      if (err_near_boundary) addr inside {[32'h0000_0100 : 32'h0000_01FC]};
      else addr inside {[32'h8000_0000 : 32'hFFFF_FF00]};
    }
  }

  constraint c_timing {
    skew_cycles   inside {[1 : 3]};
    b_ready_delay inside {[0 : 3]};
    r_ready_delay inside {[0 : 3]};
  }

endclass : axi_lite_seq_item
