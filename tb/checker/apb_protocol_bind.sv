// Bind onto the slave (Questa won't bind a module into an interface); the DUT
// ports are the APB signals, so .* connects. Needs vlog -mfcu to elaborate.
bind apb_slave apb_protocol_checker #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
) u_apb_chk (.*);
