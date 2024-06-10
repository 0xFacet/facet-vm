require 'rails_helper'

RSpec.describe CombinedProcessor do
  let(:processor) { CombinedProcessor.new(serialized_ast) }

  describe '#process' do
    context 'with simple literals' do
      it 'processes true node correctly' do
        serialized_ast = '{"type":"true","children":[]}'
        processor = CombinedProcessor.new(serialized_ast)
        expect(processor.process).to eq('__box__(true)')
      end

      it 'processes int node correctly' do
        serialized_ast = '{"type":"int","children":[1]}'
        processor = CombinedProcessor.new(serialized_ast)
        expect(processor.process).to eq('__box__(1)')
      end

      it 'processes string node correctly' do
        serialized_ast = '{"type":"str","children":["hello"]}'
        processor = CombinedProcessor.new(serialized_ast)
        expect(processor.process).to eq('__box__("hello")')
      end

      it 'processes symbol node correctly' do
        serialized_ast = '{"type":"sym","children":["my_symbol"]}'
        processor = CombinedProcessor.new(serialized_ast)
        expect(processor.process).to eq('__box__(:my_symbol)')
      end
    end

    context 'with send nodes' do
      it 'processes simple send node correctly' do
        serialized_ast = '{"type":"send","children":[null,"a",{"type":"send","children":[null,"b"]}]}'
        processor = CombinedProcessor.new(serialized_ast)
        expect(processor.process).to eq('__box__(a(__box__(b)))')
      end

      it 'processes send node with arguments correctly' do
        serialized_ast = '{"type":"send","children":[null,"add",{"type":"int","children":[1]},{"type":"int","children":[2]}]}'
        processor = CombinedProcessor.new(serialized_ast)
        expect(processor.process).to eq('__box__(add(__box__(1), __box__(2)))')
      end
    end

    context 'with if nodes' do
      it 'processes if node correctly' do
        serialized_ast = '{"type":"if","children":[{"type":"send","children":[null,"condition"]},{"type":"send","children":[null,"then_branch"]},{"type":"send","children":[null,"else_branch"]}]}'
        processor = CombinedProcessor.new(serialized_ast)
        expect(processor.process).to eq("if __get_bool__(__box__(condition))\n  __box__(then_branch)\nelse\n  __box__(else_branch)\nend")
      end
    end

    context 'with logical operations' do
      it 'processes and node correctly' do
        serialized_ast = '{"type":"and","children":[{"type":"send","children":[null,"left"]},{"type":"send","children":[null,"right"]}]}'
        processor = CombinedProcessor.new(serialized_ast)
        expect(processor.process).to eq('__box__(__get_bool__(__box__(left)) && __get_bool__(__box__(right)))')
      end

      it 'processes or node correctly' do
        serialized_ast = '{"type":"or","children":[{"type":"send","children":[null,"left"]},{"type":"send","children":[null,"right"]}]}'
        processor = CombinedProcessor.new(serialized_ast)
        expect(processor.process).to eq('__box__(__get_bool__(__box__(left)) || __get_bool__(__box__(right)))')
      end
    end

    context 'with complex structures' do
      it 'processes block nodes correctly' do
        serialized_ast = '{"type":"block","children":[{"type":"send","children":[null,"method"]},{"type":"args","children":[]},{"type":"begin","children":[{"type":"send","children":[null,"body"]}]}]}'
        processor = CombinedProcessor.new(serialized_ast)
        expect(processor.process).to eq("__box__(method {\n(__box__(body))\n})")
      end

      it 'processes array nodes correctly' do
        serialized_ast = '{"type":"array","children":[{"type":"int","children":[1]},{"type":"int","children":[2]},{"type":"int","children":[3]}]}'
        processor = CombinedProcessor.new(serialized_ast)
        expect(processor.process).to eq('__box__([__box__(1), __box__(2), __box__(3)])')
      end

      it 'processes hash nodes correctly' do
        serialized_ast = '{"type":"hash","children":[{"type":"pair","children":[{"type":"sym","children":["key1"]},{"type":"str","children":["value1"]}]},{"type":"pair","children":[{"type":"sym","children":["key2"]},{"type":"int","children":[2]}]}]}'
        processor = CombinedProcessor.new(serialized_ast)
        expect(processor.process).to eq('__box__({ key1: __box__("value1"), key2: __box__(2) })')
      end
    end

    context 'with validation' do
      it 'raises error for invalid identifier' do
        serialized_ast = '{"type":"lvasgn","children":["invalid identifier",{"type":"int","children":[1]}]}'
        processor = CombinedProcessor.new(serialized_ast)
        expect { processor.process }.to raise_error(CombinedProcessor::NodeNotAllowed, /Identifier doesn't match/)
      end

      it 'raises error for reserved word' do
        serialized_ast = '{"type":"lvasgn","children":["initialize",{"type":"int","children":[1]}]}'
        processor = CombinedProcessor.new(serialized_ast)
        expect { processor.process }.to raise_error(CombinedProcessor::NodeNotAllowed, /Use of reserved word/)
      end
    end
  end
  
  describe "#process_node" do
    let(:processor) { CombinedProcessor.new('{"type": "int", "children": [42]}') }

    it "processes integer nodes correctly" do
      expect(processor.process).to eq('__box__(42)')
    end

    it "handles nil nodes" do
      processor = CombinedProcessor.new('{"type": "nil", "children": []}')
      expect(processor.process).to eq('__box__(nil)')
    end
  end

  describe "#process_logical_operation" do
    let(:processor) { CombinedProcessor.new('{"type": "and", "children": [{"type": "true"}, {"type": "false"}]}') }

    it "processes 'and' logical operations correctly" do
      expect(processor.process).to include("__box__(__get_bool__(__box__(true)) && __get_bool__(__box__(false)))")
    end
  end

  describe "#box" do
    let(:processor) { CombinedProcessor.new('{}') }

    it "applies boxing correctly" do
      processor.box { processor.instance_variable_get(:@buffer) << "test" }
      expect(processor.instance_variable_get(:@buffer).join).to eq("__box__(test)")
    end

    it "does not apply boxing when disabled" do
      processor.box(apply_boxing: false) { processor.instance_variable_get(:@buffer) << "test" }
      expect(processor.instance_variable_get(:@buffer).join).to eq("test")
    end
  end
end
