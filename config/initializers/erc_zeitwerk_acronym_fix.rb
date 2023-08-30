class ErcFixInflector < Zeitwerk::Inflector
  def camelize(basename, abspath)
    basename.camelize.gsub(/Erc(\d+)/) { "ERC#{$1}" }
  end
end
