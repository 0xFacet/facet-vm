class ContractArtifact < ApplicationRecord
  include ContractErrors
  extend Memoist
  
  CodeIntegrityError = Class.new(StandardError)
  
  after_find :verify_ast_and_hash
  before_validation :verify_ast_and_hash_on_save
  
  after_commit :flush_cache
  delegate :reset_cache, to: :class
  
  class << self
    include ContractErrors
    extend Memoist
    
    def main_files
      Dir.glob(Rails.root.join("app/models/contracts/*.rubidity"))
    end
    
    def create_artifacts_from_files(new_files = [])
      artifact_hashes = RubidityTranspiler.transpile_multiple(new_files)
      
      existing_artifacts = ContractArtifact.all.group_by(&:name)
      
      artifact_hashes.each do |hsh|
        artifact = existing_artifacts[hsh[:name]]&.find { |a| a.init_code_hash == hsh[:init_code_hash] } || ContractArtifact.new
        artifact.assign_attributes(hsh)
    
        # Destroy all artifacts with the same name but a different init_code_hash
        (existing_artifacts[artifact.name] || []).each do |existing_artifact|
          existing_artifact.destroy unless existing_artifact.init_code_hash == artifact.init_code_hash
        end
        
        artifact.save! unless ContractArtifact.exists?(init_code_hash: artifact.init_code_hash)
    
        # Update the existing_artifacts hash
        existing_artifacts[artifact.name] = [artifact]
      end
    end
    
    def all_contract_classes
      create_artifacts_from_files(main_files)
      all.map(&:build_class).index_by(&:init_code_hash).with_indifferent_access
    end
    memoize :all_contract_classes
    
    def class_from_init_code_hash!(init_code_hash)
      hash = init_code_hash&.sub(/^0x/, '')
      all_contract_classes[hash].tap do |code|
        unless code
          raise UnknownInitCodeHash.new("No contract found with init code hash: #{init_code_hash.inspect}")
        end
      end
    end
    
    def class_from_name(name)
      all_contract_classes.values.detect do |klass|
        klass.name == name
      end
    end
    
    def build_class(ref_artifacts, source_code, name, init_code_hash)
      contract_classes = {}.with_indifferent_access

      ref_artifacts.each do |contract_name, ref_init_code_hash|
        ref_artifact = ContractArtifact.find_by(init_code_hash: ref_init_code_hash)
        
        unless ref_artifact
          raise UnknownInitCodeHash.new("No contract found with init code hash: #{ref_init_code_hash}")
        end

        contract_classes[contract_name] = ref_artifact.build_class
      end

      ContractBuilder.build_contract_class(
        available_contracts: contract_classes,
        source: source_code,
        filename: name
      ).tap do |new_class|
        if new_class.init_code_hash != init_code_hash || new_class.source_code != source_code
          raise CodeIntegrityError.new("Code integrity error")
        end
      end
    end
    memoize :build_class
    
    def types_that_implement(base_type)
      impl = class_from_name(base_type)
      contracts = all_contract_classes.values.reject(&:is_abstract_contract)
      
      contracts.select do |contract|
        contract.implements?(impl)
      end
    end
    
    def deployable_contracts
      all_contract_classes.values.reject(&:is_abstract_contract)
    end
    
    def all_abis(deployable_only: false)
      contract_classes = all_contract_classes.values
      contract_classes.reject!(&:is_abstract_contract) if deployable_only
      
      contract_classes.each_with_object({}) do |contract_class, hash|
        hash[contract_class.name] = contract_class.public_abi
      end
    end
  end

  def build_class
    self.class.build_class(references, source_code, name, init_code_hash)
  end
    
  def self.emphasized_code_exerpt(name:, line_number:)
    before_lines = 5
    after_lines = 5
    
    code = class_from_name(name).source_code
    
    lines = code.split("\n")
    start = [0, line_number - 1 - before_lines].max   # Don't go below the first line
    finish = [lines.count - 1, line_number - 1 + after_lines].min  # Don't exceed total lines
    range = (start..finish)
    
    minimum_indent = lines[range].map { |line| line[/\A */].size }.min
    
    range.each do |i|
      # Indent the line correctly
      indented_line = " " * (lines[i][/\A */].size - minimum_indent)
  
      if i == line_number - 1
        # Add '>' to the emphasized line while keeping the original indentation
        lines[i] = "#{indented_line}> #{lines[i].lstrip}"
      else
        lines[i] = "#{indented_line}  #{lines[i].lstrip}"
      end
    end
  
    lines[range].join("\n")
  end
  
  def as_json(options = {})
    super(
      options.merge(
        only: [
          :name,
          :source_code,
          :init_code_hash,
        ]
      )
    )
  end
  
  def flush_cache
    self.class.flush_cache if self.class.respond_to?(:flush_cache)
  end
  
  def self.reset_cache
    delete_all
    flush_cache
  end
  
  private
  
  def verify_ast_and_hash_on_save
    begin
      verify_ast_and_hash
    rescue CodeIntegrityError => e
      errors.add(:base, e.message)
    end
  end

  def verify_ast_and_hash
    parsed_ast = Unparser.parse(source_code).inspect

    if parsed_ast != ast
      raise CodeIntegrityError.new("AST mismatch")
    end

    if Digest::Keccak256.hexdigest(ast) != init_code_hash
      raise CodeIntegrityError.new("Hash mismatch")
    end
  end
end
