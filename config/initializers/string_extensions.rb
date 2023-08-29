class String
  def pbcopy(strip: true)
    to_copy = strip ? self.strip : self
    IO.popen('pbcopy', 'w') { |io| io.puts to_copy }
  end
end
