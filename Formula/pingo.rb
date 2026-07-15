class Pingo < Formula
  desc "Tiny network monitor for the macOS menu bar"
  homepage "https://github.com/jonasdkhansen/pingo"
  url "https://github.com/jonasdkhansen/pingo.git",
      tag:      "v1.4.0",
      revision: "ca4a2dabdd83a96cdc50cb59eeec4c87c1efe4c7"
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
