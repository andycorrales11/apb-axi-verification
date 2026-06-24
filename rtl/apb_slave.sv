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

  // TODO: Complete APB slave implementation. Currently only 2 cycle handshake is implemented, no wait states, no PSTRB handling, no error handling.

  logic [DATA_WIDTH-1:0] registers [16]; // Example: 16 32-bit registers
  logic [3:0] index; // Register index
  logic decode_err; // Address decode error flag

  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      // Reset: clear registers, set PREADY low, PRDATA 0
      for (int i = 0; i < 16; i++) begin
        registers[i] <= '0;
      end
      PREADY <= 1'b0;
      PRDATA <= '0;
    end else begin
      case ({PSEL, PENABLE})
        2'b00: begin
          // IDLE
          PREADY <= 1'b0;
          PSELVERR <= 1'b0;
        end
        2'b01: begin
          // SETUP
          PREADY <= 1'b0;
          decode_err <= | PADDR[31:6]; // Example: only addresses 0x00 to 0x3F are valid
          index <= PADDR[5:2];
        end
        2'b11: begin
          // ACCESS
          if (decode_err) begin
            // Invalid address
            PSLVERR <= 1'b1;
          end else begin
            // Valid address
            PSLVERR <= 1'b0;
            if (PWRITE) begin // WRITE
            // TODO: Handle PSTRB for partial writes
              registers[index] <= PWDATA;
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
