# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::LZMA::XzProbabilityModels do
  let(:lc) { 3 }
  let(:lp) { 0 }
  let(:pb) { 2 }
  let(:models) { described_class.new(lc, lp, pb) }

  describe "#initialize" do
    it "creates literal models with correct dimensions" do
      # XZ Utils uses a FLAT array structure: LITERAL_CODER_SIZE << (lc + lp)
      # For lc=3, lp=0: 0x300 * 8 = 6144 models
      expected_size = 0x300 << (lc + lp)
      expect(models.literal.size).to eq(expected_size)
      expect(models.literal[0]).to be_a(Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder::Probability)
    end

    it "initializes all literal models to default probability" do
      init_prob = Omnizip::Algorithms::LZMA::Constants::INIT_PROBS
      models.literal.each do |model|
        expect(model.probability).to eq(init_prob)
      end
    end

    it "creates match models with correct dimensions" do
      num_states = Omnizip::Algorithms::LZMA::Constants::NUM_STATES
      num_pos_states = 1 << pb

      expect(models.is_match.size).to eq(num_states)
      expect(models.is_match[0].size).to eq(num_pos_states)
      expect(models.is_rep.size).to eq(num_states)
      expect(models.is_rep0.size).to eq(num_states)
      expect(models.is_rep1.size).to eq(num_states)
      expect(models.is_rep2.size).to eq(num_states)
      expect(models.is_rep0_long.size).to eq(num_states)
      expect(models.is_rep0_long[0].size).to eq(num_pos_states)
    end

    it "creates distance models with correct dimensions" do
      expect(models.dist_slot.size).to eq(4) # NUM_LEN_TO_POS_STATES
      expect(models.dist_slot[0].size).to eq(64) # NUM_DIST_SLOTS
      expect(models.dist_align.size).to eq(16) # DIST_ALIGN_SIZE
    end

    it "creates length encoders" do
      expect(models.match_len_encoder).to be_a(Omnizip::Algorithms::LZMA::LengthEncoder)
      expect(models.rep_len_encoder).to be_a(Omnizip::Algorithms::LZMA::LengthEncoder)
    end
  end

  describe "#reset" do
    it "resets all literal models to initial probability" do
      init_prob = Omnizip::Algorithms::LZMA::Constants::INIT_PROBS

      # Modify some models (flat array structure)
      models.literal[0].update(0)
      models.literal[1].update(1)
      expect(models.literal[0].probability).not_to eq(init_prob)

      # Reset
      models.reset

      # Check all are reset (flat array)
      models.literal.each do |model|
        expect(model.probability).to eq(init_prob)
      end
    end

    it "resets all match models" do
      init_prob = Omnizip::Algorithms::LZMA::Constants::INIT_PROBS

      # Modify
      models.is_match[0][0].update(0)
      models.is_rep[0].update(1)

      # Reset
      models.reset

      # Verify
      models.is_match.each do |ps|
        ps.each do |m|
          expect(m.probability).to eq(init_prob)
        end
      end
      models.is_rep.each { |m| expect(m.probability).to eq(init_prob) }
      models.is_rep0.each { |m| expect(m.probability).to eq(init_prob) }
      models.is_rep1.each { |m| expect(m.probability).to eq(init_prob) }
      models.is_rep2.each { |m| expect(m.probability).to eq(init_prob) }
      models.is_rep0_long.each do |ps|
        ps.each do |m|
          expect(m.probability).to eq(init_prob)
        end
      end
    end

    it "resets all distance models" do
      init_prob = Omnizip::Algorithms::LZMA::Constants::INIT_PROBS

      # Modify
      models.dist_slot[0][0].update(0)
      models.dist_align[0].update(1)

      # Reset
      models.reset

      # Verify
      models.dist_slot.each do |slots|
        slots.each do |m|
          expect(m.probability).to eq(init_prob)
        end
      end
      models.dist_special.each { |m| expect(m.probability).to eq(init_prob) }
      models.dist_align.each { |m| expect(m.probability).to eq(init_prob) }
    end
  end

  describe "model access" do
    it "allows access to specific literal model" do
      # XZ Utils uses flat array: index = (symbol << (lc + lp)) + context
      # For symbol=0x100, lc=3, lp=0: index = 0x100 * 8 + context
      symbol_idx = 0x100
      context_idx = 0
      flat_index = (symbol_idx << (lc + lp)) + context_idx
      model = models.literal[flat_index]
      expect(model).to be_a(Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder::Probability)
    end

    it "allows access to specific match model" do
      state = 0
      pos_state = 0
      model = models.is_match[state][pos_state]
      expect(model).to be_a(Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder::Probability)
    end

    it "supports model updates" do
      init_prob = Omnizip::Algorithms::LZMA::Constants::INIT_PROBS
      model = models.is_rep[0]

      model.update(0)
      expect(model.probability).to be > init_prob

      model.update(1)
      expect(model.probability).to be < init_prob
    end
  end
end

RSpec.describe Omnizip::Algorithms::LZMA::LengthEncoder do
  let(:pb) { 2 }
  let(:encoder) { described_class.new(pb) }

  describe "#initialize" do
    it "creates choice models" do
      expect(encoder.choice).to be_a(Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder::Probability)
      expect(encoder.choice2).to be_a(Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder::Probability)
    end

    it "creates low models with correct dimensions" do
      num_pos_states = 1 << pb
      expect(encoder.low.size).to eq(num_pos_states)
      expect(encoder.low[0].size).to eq(8) # LEN_LOW_SYMBOLS
    end

    it "creates mid models with correct dimensions" do
      num_pos_states = 1 << pb
      expect(encoder.mid.size).to eq(num_pos_states)
      expect(encoder.mid[0].size).to eq(8) # LEN_MID_SYMBOLS
    end

    it "creates high models with correct dimensions" do
      expect(encoder.high.size).to eq(256) # LEN_HIGH_SYMBOLS
    end

    it "initializes price tables" do
      num_pos_states = 1 << pb
      max_len = Omnizip::Algorithms::LZMA::Constants::MATCH_LEN_MAX
      min_len = Omnizip::Algorithms::LZMA::Constants::MATCH_LEN_MIN

      expect(encoder.prices.size).to eq(num_pos_states)
      expect(encoder.prices[0].size).to eq(max_len - min_len + 1)
    end

    it "initializes price counters" do
      num_pos_states = 1 << pb
      expect(encoder.counters.size).to eq(num_pos_states)
      expect(encoder.counters).to all(eq(0))
    end
  end

  describe "#reset" do
    it "resets all models to initial probability" do
      init_prob = Omnizip::Algorithms::LZMA::Constants::INIT_PROBS

      # Modify
      encoder.choice.update(0)
      encoder.low[0][0].update(1)

      # Reset
      encoder.reset

      # Verify
      expect(encoder.choice.probability).to eq(init_prob)
      expect(encoder.choice2.probability).to eq(init_prob)
      encoder.low.each do |models|
        models.each do |m|
          expect(m.probability).to eq(init_prob)
        end
      end
      encoder.mid.each do |models|
        models.each do |m|
          expect(m.probability).to eq(init_prob)
        end
      end
      encoder.high.each { |m| expect(m.probability).to eq(init_prob) }
    end

    it "resets price tables to zero" do
      # Set prices
      encoder.set_price(0, 10, 100)
      expect(encoder.get_price(0, 10)).to eq(100)

      # Reset
      encoder.reset

      # Verify
      expect(encoder.get_price(0, 10)).to eq(0)
      encoder.prices.each { |pos_prices| expect(pos_prices).to all(eq(0)) }
    end

    it "resets counters to zero" do
      encoder.reset_counter(0, 10)
      expect(encoder.counters[0]).to eq(10)

      encoder.reset

      expect(encoder.counters).to all(eq(0))
    end
  end

  describe "#get_price and #set_price" do
    it "stores and retrieves prices correctly" do
      pos_state = 1
      length = 10
      price = 500

      encoder.set_price(pos_state, length, price)
      expect(encoder.get_price(pos_state, length)).to eq(price)
    end

    it "handles minimum length (2)" do
      encoder.set_price(0, 2, 100)
      expect(encoder.get_price(0, 2)).to eq(100)
    end

    it "handles maximum length (273)" do
      encoder.set_price(0, 273, 999)
      expect(encoder.get_price(0, 273)).to eq(999)
    end
  end

  describe "#decrement_counter" do
    it "decrements counter and returns false when positive" do
      encoder.reset_counter(0, 10)
      expect(encoder.decrement_counter(0)).to be false
      expect(encoder.counters[0]).to eq(9)
    end

    it "returns true when counter reaches zero" do
      encoder.reset_counter(0, 1)
      expect(encoder.decrement_counter(0)).to be true
      expect(encoder.counters[0]).to eq(0)
    end

    it "returns true when counter goes negative" do
      encoder.reset_counter(0, 0)
      expect(encoder.decrement_counter(0)).to be true
      expect(encoder.counters[0]).to eq(-1)
    end
  end

  describe "#reset_counter" do
    it "sets counter to specified value" do
      encoder.reset_counter(0, 100)
      expect(encoder.counters[0]).to eq(100)

      encoder.reset_counter(1, 50)
      expect(encoder.counters[1]).to eq(50)
    end
  end
end

RSpec.describe Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder::Probability do
  describe "inline probability updates" do
    it "updates probability model after encoding bits" do
      # Test that encode_bit happens BEFORE prob.update
      # This is critical for LZMA correctness
      prob = Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder::Probability.new(0x400)
      initial_value = prob.value

      # Encode a bit and check if prob changed
      output = StringIO.new
      encoder = Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder.new(output)
      encoder.queue_bit(prob, 0)

      # Probability should NOT change during queueing (deferred encoding)
      expect(prob.value).to eq(initial_value)

      # Now encode the symbols
      out = output.string
      out_pos = Omnizip::Algorithms::LZMA::IntRef.new(0)
      encoder.encode_symbols(out, out_pos, 1024)

      # After encoding, probability should be updated
      # For bit=0, probability should increase
      expect(prob.value).to be > initial_value
    end

    it "updates probability for bit=0 (increases probability)" do
      # When encoding bit 0, probability of 0 should increase
      prob = Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder::Probability.new(0x400)
      initial_value = prob.value

      output = StringIO.new
      encoder = Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder.new(output)
      encoder.queue_bit(prob, 0)

      out = output.string
      out_pos = Omnizip::Algorithms::LZMA::IntRef.new(0)
      encoder.encode_symbols(out, out_pos, 1024)

      # prob.value += (BIT_MODEL_TOTAL - prob.value) >> MOVE_BITS
      expected_increase = (Omnizip::Algorithms::LZMA::Constants::BIT_MODEL_TOTAL - initial_value) >> Omnizip::Algorithms::LZMA::Constants::MOVE_BITS
      expect(prob.value).to eq(initial_value + expected_increase)
    end

    it "updates probability for bit=1 (decreases probability)" do
      # When encoding bit 1, probability of 0 should decrease
      prob = Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder::Probability.new(0x400)
      initial_value = prob.value

      output = StringIO.new
      encoder = Omnizip::Algorithms::LZMA::XzBufferedRangeEncoder.new(output)
      encoder.queue_bit(prob, 1)

      out = output.string
      out_pos = Omnizip::Algorithms::LZMA::IntRef.new(0)
      encoder.encode_symbols(out, out_pos, 1024)

      # prob.value -= prob.value >> MOVE_BITS
      expected_decrease = initial_value >> Omnizip::Algorithms::LZMA::Constants::MOVE_BITS
      expect(prob.value).to eq(initial_value - expected_decrease)
    end
  end
end
