require 'rails_helper'

RSpec.describe ImportResolver do
  let(:initial_filename) { File.expand_path('../../fixtures/BottomLevelImporter.rubidity', __FILE__) }
  let(:unused_reference) { File.expand_path('../../fixtures/TestUnusedReference.rubidity', __FILE__) }

  describe '#process_file' do
    it 'correctly processes file with imports' do
      
      processed_ast = ImportResolver.process(initial_filename)
      
      first_node = processed_ast.children.first
      expect(first_node.type).to eq(:send)
      expect(first_node.children[1]).to eq(:pragma)
      expect(first_node.children[2].children[0]).to eq(:rubidity)
      expect(first_node.children[3].children[0]).to eq("1.0.0")

      # Check that there is exactly one pragma statement
      pragma_count = processed_ast.children.count do |node|
        node.type == :send && node.children[1] == :pragma
      end
      expect(pragma_count).to eq(1)
    end
    
    it "excludes unused imports" do
       classes = RubidityFile.new(unused_reference).contract_classes
       expect(classes.last.source_code.split.length).to be < 20
    end
  end
end
