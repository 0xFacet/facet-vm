require 'rails_helper'

RSpec.describe ForLoop do
  class DummyClass
    include ForLoop
  end

  let(:dummy_class) { DummyClass.new }

  describe '#for_loop' do
    it 'skips even numbers' do
      ary = (1..10).to_a
      result = []

      dummy_class.for_loop(start: 0, condition: ->(i) { i < ary.length }, step: 1, max_iterations: 100) do |i|
        next if i.even?
        result << i
      end

      expect(result).to eq([1, 3, 5, 7, 9])
    end

    it 'stops the loop when i is greater than 5' do
      ary = (1..10).to_a
      result = []

      dummy_class.for_loop(start: 0, condition: ->(i) { i < ary.length }, step: 1, max_iterations: 100) do |i|
        break if i > 5
        result << i
      end

      expect(result).to eq([0, 1, 2, 3, 4, 5])
    end

    it 'raises an error when max iterations are exceeded' do
      ary = (1..10).to_a

      expect {
        dummy_class.for_loop(start: 0, condition: ->(i) { i < ary.length }, step: 1, max_iterations: 5) do |i|
        end
      }.to raise_error(StandardError, "MaxIterationsExceeded")
    end
    
    it 'runs with default arguments' do
      result = []
      dummy_class.for_loop(condition: ->(i) { i < 5 }, max_iterations: 100) do |i|
        result << i
      end
      expect(result).to eq([0, 1, 2, 3, 4])
    end
    
    it 'decrements with a negative step' do
      result = []
      dummy_class.for_loop(start: 5, condition: ->(i) { i >= 0 }, step: -1, max_iterations: 100) do |i|
        result << i
      end
      expect(result).to eq([5, 4, 3, 2, 1, 0])
    end
    
    it 'never runs if condition is immediately false' do
      result = []
      dummy_class.for_loop(start: 10, condition: ->(i) { i < 5 }, max_iterations: 100) do |i|
        result << i
      end
      expect(result).to be_empty
    end
    
    it 'handles non-integer steps' do
      result = []
      dummy_class.for_loop(start: 0, condition: ->(i) { i < 5 }, step: 0.5, max_iterations: 100) do |i|
        result << i
      end
      expect(result).to eq([0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5])
    end
    
    it 'increments by custom step value' do
      result = []
      dummy_class.for_loop(start: 0, condition: ->(i) { i < 10 }, step: 2, max_iterations: 100) do |i|
        result << i
      end
      expect(result).to eq([0, 2, 4, 6, 8])
    end
    
    it 'handles nested for_loops correctly' do
      outer_results = []
      inner_results = []
    
      dummy_class.for_loop(start: 0, condition: ->(i) { i < 3 }, step: 1, max_iterations: 5) do |i|
        outer_results << i
    
        dummy_class.for_loop(start: 10, condition: ->(j) { j < 13 }, step: 1, max_iterations: 5) do |j|
          inner_results << j
        end
      end
    
      expect(outer_results).to eq([0, 1, 2])
      expect(inner_results).to eq([10, 11, 12, 10, 11, 12, 10, 11, 12])
    end    
  end
end
