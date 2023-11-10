class ContractCodeVersion < ApplicationRecord
  CodeIntegrityError = Class.new(StandardError)
  
  after_find :verify_ast_and_hash
  before_validation :verify_ast_and_hash_on_save
  
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
      raise CodeIntegrityError, "AST mismatch"
    end

    if Digest::Keccak256.hexdigest(ast) != init_code_hash
      raise CodeIntegrityError, "Hash mismatch"
    end
  end
end
