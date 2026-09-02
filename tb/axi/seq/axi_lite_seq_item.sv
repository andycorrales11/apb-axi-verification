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
  // dir is NOT rand: it is a shaping choice, drawn in pre_randomize(). See there.
  axi_dir_e                         dir;
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
  // NOT rand: drawn in pre_randomize(). See the note there.
  axi_addr_class_e      addr_class;
  rand bit              err_near_boundary;
  // The bridge special-cases zero-strobe writes (axi_lite_to_apb.sv:299): no
  // APB transfer, answer OKAY -- even out of map, masking a DECERR. Shaped
  // deliberately rather than left to a 1/16 chance on a free `rand strb`.
  // NOT rand, same reason as addr_class.
  bit                   zero_strb;

  // ---- results: filled by the driver/monitor, NOT randomized ----
  logic [AXI_DATA_WIDTH-1:0] rdata;
  logic [1:0]                resp;

  function new(string name = "axi_lite_seq_item");
    super.new(name);
  endfunction

  // The rule this class follows: **the solver picks values, pre_randomize picks
  // selectors.** Any field that selects which branch of a constraint applies is
  // drawn here; the solver only fills in a payload within the branch it was
  // handed. Leaving a selector rand does not do what it looks like it does.
  //
  // Why. The solver does not sample a selector by its weight, it samples the
  // joint (selector, payload) space, so the selector's frequency tracks how many
  // payload values its branch permits:
  //   - addr_class: at 200 transactions an intended 127/36/36 came out 42/79/79,
  //     inverted, because ADDR_REG permits 16 addresses against ADDR_DECERR's
  //     millions. Only 42 of 200 transactions touched a real register.
  //   - zero_strb: it is also coupled to dir through c_strb, since zero_strb==1
  //     forces strb == '0 down both dir branches and zero_strb==0 does not. So
  //     conditioning on writes reskews it: drawn at 20%, it reached coverage as
  //     34% of writes.
  //   - dir: c_strb gives AXI_READ one legal strb against AXI_WRITE's fifteen.
  //     A cut-down model of just dir/strb/zero_strb put P(WRITE) at 0.77; in the
  //     full item, with addr/data/prot/timing also in the solve, it was much
  //     milder (~0.53). Drawn here regardless -- it is a selector, and the size
  //     of the distortion depends on the rest of the constraint set.
  //
  // `solve ... before` does not fix this. For addr_class it changed nothing at
  // all (same seed, REG=42 with and without). For zero_strb it looked like a fix
  // -- 15/103 became 20/87 -- but that was a small sample; once addr_class moved
  // and the stream shifted, the same constraint gave 33/96. The RNG was cleared
  // as a suspect first: $urandom_range measured flat over 200k draws, reseeded
  // and not.
  //
  // After the change, over seeds 1/2/3/7/42/99: class mix averages 122.8/38.2/
  // 39.0 against 127.3/36.4/36.4, writes average 99.0 of 200, and zero-strobe
  // writes are 121 of 594 (20.4%).
  function void pre_randomize();
    int unsigned pick = $urandom_range(10);
    if (pick < 7) addr_class = ADDR_REG;
    else if (pick < 9) addr_class = ADDR_SLVERR;
    else addr_class = ADDR_DECERR;
    dir       = ($urandom_range(1) == 1) ? AXI_WRITE : AXI_READ;
    zero_strb = ($urandom_range(9) < 2);  // 20% of writes; inert on reads
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

  // Reads carry no strobe; the bridge forces '0 on the read path
  // (axi_lite_to_apb.sv:117), so pin it to keep the cross-check unambiguous.
  constraint c_strb {
    if (dir == AXI_READ) {
      strb == '0;
    } else {
      if (zero_strb) strb == '0;
      else strb != '0;
    }
  }

  constraint c_timing {
    skew_cycles   inside {[1 : 3]};
    b_ready_delay inside {[0 : 3]};
    r_ready_delay inside {[0 : 3]};
  }

endclass : axi_lite_seq_item
