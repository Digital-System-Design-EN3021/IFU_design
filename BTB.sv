// ============================================================================
// Branch Target Buffer (BTB) Module
// ============================================================================
module BTB #(
    parameter BTB_SIZE = 64,           // Number of BTB entries
    parameter ADDR_WIDTH = 32,         // Address width
    parameter INDEX_BITS = 6           // log2(BTB_SIZE) = 6 bits for indexing
)(
    input  logic                    clk,
    input  logic                    reset,
    
    // --- Lookup Interface (Predict) ---
    input  logic [ADDR_WIDTH-1:0]   lookup_pc,         // PC to lookup
    output logic [ADDR_WIDTH-1:0]   target_addr,       // Predicted target address
    output logic                    btb_hit,           // 1 if entry found, 0 otherwise
    
    // --- Update Interface (from Execute/Commit stage) ---
    input  logic                    update_valid,      // Update enable
    input  logic [ADDR_WIDTH-1:0]   update_pc,         // PC of branch instruction
    input  logic [ADDR_WIDTH-1:0]   update_target,     // Actual target address
    input  logic                    is_branch          // 1 if this is a branch instruction
);

    // BTB Entry Structure
    typedef struct packed {
        logic                   valid;      // Entry is valid
        logic [ADDR_WIDTH-1:0]  tag;        // Tag for matching
        logic [ADDR_WIDTH-1:0]  target;     // Target address
    } btb_entry_t;
    
    // BTB Storage Array
    btb_entry_t btb_array [BTB_SIZE-1:0];
    
    // Index calculation: Use lower bits of PC for direct mapping
    logic [INDEX_BITS-1:0] lookup_index;
    logic [INDEX_BITS-1:0] update_index;
    logic [ADDR_WIDTH-1:0] lookup_tag;
    logic [ADDR_WIDTH-1:0] update_tag;
    
    assign lookup_index = lookup_pc[INDEX_BITS+1:2];  // Skip lower 2 bits (word-aligned)
    assign update_index = update_pc[INDEX_BITS+1:2];
    assign lookup_tag   = lookup_pc[ADDR_WIDTH-1:INDEX_BITS+2]; // Upper bits as tag
    assign update_tag   = update_pc[ADDR_WIDTH-1:INDEX_BITS+2];
    
    // --- Lookup Logic (Combinational) ---
    always_comb begin
        if (btb_array[lookup_index].valid && 
            (btb_array[lookup_index].tag == lookup_tag)) begin
            btb_hit     = 1'b1;
            target_addr = btb_array[lookup_index].target;
        end else begin
            btb_hit     = 1'b0;
            target_addr = '0;
        end
    end
    
    // --- Update Logic (Sequential) ---
    always_ff @(posedge clk) begin
        if (reset) begin
            for (integer i = 0; i < BTB_SIZE; i++) begin
                btb_array[i].valid  <= 1'b0;
                btb_array[i].tag    <= '0;
                btb_array[i].target <= '0;
            end
        end else if (update_valid && is_branch) begin
            // Update BTB entry doesnt care about the tie , replace earlier one need to add tier braker (LRU)
            btb_array[update_index].valid  <= 1'b1;
            btb_array[update_index].tag    <= update_tag;
            btb_array[update_index].target <= update_target;
        end
    end

endmodule

