module AttrPublicReadPrivateWrite
  def attr_public_read_private_write(*names)
    attr_accessor(*names)

    names.each do |name|
      private "#{name}="
    end
  end
end
