class ContractArtifact < ApplicationRecord
  CodeIntegrityError = Class.new(StandardError)
  
  include ContractErrors
  extend Memoist
  
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true
  has_many :contracts, foreign_key: :current_init_code_hash, primary_key: :init_code_hash
  
  scope :newest_first, -> {
    order(
      block_number: :desc,
      transaction_index: :desc,
      internal_transaction_index: :desc
    ) 
  }
  
  attr_accessor :abi
  
  after_find :verify_ast_and_hash
  before_validation :verify_ast_and_hash_on_save
  
  after_commit :flush_cache
  
  class << self
    include ContractErrors
    extend Memoist
    
    def latest_tx_hash
      newest_first.limit(1).pluck(:transaction_hash).first
    end
    
    def init_code_to_class
      @init_code_to_class ||= {}
    end
    
    def cached_class_as_of_tx_hash(init_code_hash)
      if init_code_to_class.key?(init_code_hash)
        # TODO: replace with cache that works with simulate_with_state
        # return init_code_to_class[init_code_hash]
      end
      
      res = find_by(init_code_hash: init_code_hash)&.build_class
      
      if res
        init_code_to_class[init_code_hash] = res
      end
      
      res
    end
    
    def all_contract_classes
      all.map(&:build_class).index_by(&:init_code_hash).with_indifferent_access
    end
    memoize :all_contract_classes
    
    # TODO: remove
    def class_from_name(name)
      artifacts = where(name: name)
      
      if artifacts.count > 1
        raise "Multiple artifacts found with name: #{name.inspect}"
      end
      
      artifact = artifacts.first
      
      unless artifact
        raise UnknownContractName.new("No contract found with name: #{name.inspect}")
      end
      
      artifact.build_class
    end
    
    def build_class(artifact_attributes)
      artifact = new(artifact_attributes)
      ContractBuilder.build_contract_class(artifact).tap do |new_class|
        # TODO: validate the hash is the hash of the code
        if new_class.init_code_hash != artifact.init_code_hash || new_class.source_code != artifact.source_code
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
      current_artifact_classes = SystemConfigVersion.current_supported_contract_artifacts.map(&:build_class)
      contract_classes = all_contract_classes.values + current_artifact_classes
      contract_classes = contract_classes.uniq(&:init_code_hash)
      contract_classes.reject!(&:is_abstract_contract) if deployable_only
      
      contract_classes.each_with_object({}) do |contract_class, hash|
        hash[contract_class.name] = contract_class.abi.as_json
      end
    end
  end
  
  def execution_source_code
    TransactionContext.log_call("ContractCreation", "ContractArtifact#execution_source_code") do
      @_execution_source_code ||= ConstsToSends.process(source_code)
    end
  end
  
  # def self.execution_source_code_batch(artifacts)
  #   TransactionContext.log_call("ContractCreation", "ContractArtifact.execution_source_code_batch") do
  #     Parallel.map(artifacts, in_processes: 16) do |artifact|
  #       puts "starting #{artifact.name} at #{Time.now.to_i}"
  #       artifact.execution_source_code
  #       artifact
  #     end
  #   end
  # end
  
  def set_abi
    self.abi = build_class.abi
  end
  
  def dependencies_and_self
    as_objs = references.map do |dep|
      self.class.new(dep.to_h)
    end
    
    as_objs << self
    
    # self.class.execution_source_code_batch(as_objs)
  end
  
  def build_class
    self.class.build_class(self.attributes.deep_dup)
  end
    
  def self.emphasized_code_exerpt(name:, line_number:)
    return
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
          :init_code_hash
        ],
        methods: [
          :abi,
          :execution_source_code
        ]
      )
    )
  end
  
  def flush_cache
    self.class.flush_cache if self.class.respond_to?(:flush_cache)
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
    hsh = "0x" + Digest::Keccak256.hexdigest(parsed_ast)

    if hsh != init_code_hash
      raise CodeIntegrityError.new("Hash mismatch")
    end
  end
end
