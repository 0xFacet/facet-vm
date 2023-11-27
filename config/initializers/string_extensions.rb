class String
  def pbcopy(strip: true)
    to_copy = strip ? self.strip : self
    Clipboard.copy(to_copy)
    nil
  end
end
