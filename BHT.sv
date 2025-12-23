
// ============================================================================
// Branch History Table (BHT) with 2-bit Saturating Counter Predictor
// ============================================================================
module BHT #(
    parameter BHT_SIZE = 256,          // Number of BHT entries
    parameter ADDR_WIDTH = 32,         // Address width
    parameter INDEX_BITS = 8           // log2(BHT_SIZE) = 8 bits for indexing
)(
    input  logic                    clk,
    input  logic                    reset,
    
    // --- Prediction Interface ---
    input  logic [ADDR_WIDTH-1:0]   predict_pc,        // PC to predict
    output logic                    prediction,        // 1 = taken, 0 = not taken
    output logic [1:0]              confidence,        // 2-bit counter value
    
    // --- Update Interface (from Execute/Commit stage) ---
    input  logic                    update_valid,      // Update enable
    input  logic [ADDR_WIDTH-1:0]   update_pc,         // PC of branch instruction
    input  logic                    actual_taken,      // Actual branch outcome
    input  logic                    is_branch          // 1 if this is a branch
);

    // 2-bit Saturating Counter States
    typedef enum logic [1:0] {
        STRONG_NOT_TAKEN = 2'b00,
        WEAK_NOT_TAKEN   = 2'b01,
        WEAK_TAKEN       = 2'b10,
        STRONG_TAKEN     = 2'b11
    } predictor_state_t;
    
    // BHT Storage Array: 2-bit counter for each entry
    logic [1:0] bht_array [BHT_SIZE-1:0];
    
    // Index calculation
    logic [INDEX_BITS-1:0] predict_index;
    logic [INDEX_BITS-1:0] update_index;
    
    assign predict_index = predict_pc[INDEX_BITS+1:2];  // Skip lower 2 bits
    assign update_index  = update_pc[INDEX_BITS+1:2];
    
    // --- Prediction Logic (Combinational) ---
    always_comb begin
        confidence = bht_array[predict_index];
        // Predict taken if counter >= 2 (WEAK_TAKEN or STRONG_TAKEN)
        prediction = bht_array[predict_index][1];
    end
    
    // --- Update Logic (Sequential) - 2-bit Saturating Counter ---
    always_ff @(posedge clk) begin
        if (reset) begin
            for (integer i = 0; i < BHT_SIZE; i++) begin
                bht_array[i] <= WEAK_NOT_TAKEN;  // Initialize to weakly not taken
            end
        end else if (update_valid && is_branch) begin
            // Update 2-bit saturating counter
            case (bht_array[update_index])
                STRONG_NOT_TAKEN: begin
                    if (actual_taken)
                        bht_array[update_index] <= WEAK_NOT_TAKEN;
                    // else stay in STRONG_NOT_TAKEN
                end
                
                WEAK_NOT_TAKEN: begin
                    if (actual_taken)
                        bht_array[update_index] <= WEAK_TAKEN;
                    else
                        bht_array[update_index] <= STRONG_NOT_TAKEN;
                end
                
                WEAK_TAKEN: begin
                    if (actual_taken)
                        bht_array[update_index] <= STRONG_TAKEN;
                    else
                        bht_array[update_index] <= WEAK_NOT_TAKEN;
                end
                
                STRONG_TAKEN: begin
                    if (!actual_taken)
                        bht_array[update_index] <= WEAK_TAKEN;
                    // else stay in STRONG_TAKEN
                end
            endcase
        end
    end

endmodule


// ============================================================================
// Combined Branch Prediction Unit (BTB + BHT)
// ============================================================================
module Branch_Prediction_Unit #(
    parameter BTB_SIZE = 64,
    parameter BHT_SIZE = 256,
    parameter ADDR_WIDTH = 32,
    parameter BTB_INDEX_BITS = 6,
    parameter BHT_INDEX_BITS = 8
)(
    input  logic                    clk,
    input  logic                    reset,
    
    // --- Prediction Interface (Fetch Stage) ---
    input  logic [ADDR_WIDTH-1:0]   fetch_pc,              // Current PC
    output logic                    predict_taken,         // Final prediction
    output logic [ADDR_WIDTH-1:0]   predict_target,        // Predicted target
    output logic                    prediction_valid,      // Prediction is valid
    
    // --- Update Interface (Execute/Commit Stage) ---
    input  logic                    update_valid,          // Update enable
    input  logic [ADDR_WIDTH-1:0]   update_pc,             // Branch PC
    input  logic [ADDR_WIDTH-1:0]   update_target,         // Actual target
    input  logic                    actual_taken,          // Actual outcome
    input  logic                    is_branch              // Is branch instruction
);

    // Signals from BTB
    logic [ADDR_WIDTH-1:0] btb_target;
    logic                  btb_hit;
    
    // Signals from BHT
    logic                  bht_prediction;
    logic [1:0]            bht_confidence;
    
    // --- Instantiate BTB ---
    BTB #(
        .BTB_SIZE(BTB_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .INDEX_BITS(BTB_INDEX_BITS)
    ) btb_inst (
        .clk(clk),
        .reset(reset),
        .lookup_pc(fetch_pc),
        .target_addr(btb_target),
        .btb_hit(btb_hit),
        .update_valid(update_valid),
        .update_pc(update_pc),
        .update_target(update_target),
        .is_branch(is_branch)
    );
    
    // --- Instantiate BHT ---
    BHT #(
        .BHT_SIZE(BHT_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .INDEX_BITS(BHT_INDEX_BITS)
    ) bht_inst (
        .clk(clk),
        .reset(reset),
        .predict_pc(fetch_pc),
        .prediction(bht_prediction),
        .confidence(bht_confidence),
        .update_valid(update_valid),
        .update_pc(update_pc),
        .actual_taken(actual_taken),
        .is_branch(is_branch)
    );
    
    // --- Combine BTB and BHT Predictions ---
    always_comb begin
        // Prediction is valid if BTB hits and BHT predicts taken
        prediction_valid = btb_hit && bht_prediction;
        predict_taken    = bht_prediction;
        predict_target   = btb_target;
        
        // Alternative: Only predict taken if both BTB hits AND BHT predicts taken
        // This reduces false predictions but may miss some branches
    end

endmodule

