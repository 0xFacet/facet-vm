require 'rails_helper'

RSpec.describe ImportResolver do
  let(:initial_filename) { File.expand_path('../../fixtures/BottomLevelImporter.rubidity', __FILE__) }
  # let(:higher_level_filename) { File.expand_path('../../fixtures/HigherLevelImporter.rubidity', __FILE__) }
  # let(:resolver) { ImportResolver.new(initial_filename) }

  describe '#process_file' do
    it 'correctly processes file with imports' do
      # Read initial file
      
      # resolver = ImportResolver.new(initial_filename)
      
      # processed_ast = resolver.process_file(initial_filename)
      processed_ast = ImportResolver.process(initial_filename)
      
      # puts Unparser.unparse(processed_ast)
      
      # pp processed_ast.children.map(&:type)
      # pp processed_ast.children.map{|i| i.children.first.children.third rescue nil}
      
      # binding.pry
      
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
    
    it "respects import order and avoids duplicate imports" do
      # resolver = ImportResolver.new(higher_level_filename)
      # processed_ast = resolver.process_file(higher_level_filename)
    end
  end
end
