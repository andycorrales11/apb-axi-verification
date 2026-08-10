module apb_slave #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input  logic                  PCLK,
    input  logic                  PRESETn,
    input  logic [ADDR_WIDTH-1:0] PADDR,
    input  logic [           2:0] PPROT,
    input  logic                  PSEL,
    input  logic                  PENABLE,
    input  logic                  PWRITE,
    input  logic [DATA_WIDTH-1:0] PWDATA,
    input  logic [DATA_WIDTH/8-1:0] PSTRB,
    output logic                  PREADY,
    output logic [DATA_WIDTH-1:0] PRDATA,
    output logic                  PSLVERR
);

  // 2-cycle handshake (no wait states), PSTRB byte enables, PSLVERR on
  // out-of-range addresses.

  logic [DATA_WIDTH-1:0] registers [16];
  logic [3:0] index;
  logic decode_err;

  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      for (int i = 0; i < 16; i++) begin
        registers[i] <= '0;
      end
      PREADY <= 1'b0;
      PRDATA <= '0;
      PSLVERR <= 1'b0;
      decode_err <= 1'b0;
      index <= '0;
    end else begin
      case ({PSEL, PENABLE})
        2'b00: begin
          // IDLE
          PREADY <= 1'b0;
          PSLVERR <= 1'b0;
        end
        2'b10: begin
          // SETUP (PSEL asserted, PENABLE still low)
          PREADY <= 1'b0;
          decode_err <= | PADDR[31:6]; // only addresses 0x00 to 0x3F are valid
          index <= PADDR[5:2];
        end
        2'b11: begin
          // ACCESS
          if (decode_err) begin
            PSLVERR <= 1'b1;
          end else begin
            PSLVERR <= 1'b0;
            if (PWRITE) begin // WRITE
              // PSTRB byte enables: only enabled lanes update
              for (int i = 0; i < DATA_WIDTH/8; i++) begin
                if (PSTRB[i]) registers[index][i*8 +: 8] <= PWDATA[i*8 +: 8];
              end
            end else begin // READ
              PRDATA <= registers[index];
            end
          end
          PREADY <= 1'b1;
        end
        default: begin
          // Invalid state
          PREADY <= 1'b0;
        end
      endcase
    end
  end


endmodule : apb_slave
