class Pingo < Formula
  desc "Tiny network monitor for the macOS menu bar"
  homepage "https://github.com/jonasdkhansen/pingo"
  url "https://github.com/jonasdkhansen/pingo.git",
      tag:      "v1.5.2",
      revision: "3c3b1a82c44e54f680e0f85fd7e83fe400ca784c"
  license "Apache-2.0"

  depends_on macos: :big_sur

  def install
    # build.sh refuses to build while Pingo is running so that macOS can
    # validate the app signature on the developer's own machine. Homebrew
    # always builds in an isolated temporary directory, so that guard is
    # unnecessary (and would otherwise block installs while a user has
    # Pingo open).
    inreplace "build.sh", "if pgrep -x Pingo >/dev/null; then", "if false; then"

    system "./build.sh"
    prefix.install "Pingo.app"

    (bin/"pingo").write <<~SH
      #!/bin/bash
      open "#{opt_prefix}/Pingo.app"
    SH
    chmod 0755, bin/"pingo"
  end

  test do
    assert_predicate prefix/"Pingo.app/Contents/MacOS/Pingo", :executable?
    system "codesign", "--verify", "--deep", "--strict", prefix/"Pingo.app"
  end
end
