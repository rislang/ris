require "./spec_helper"

describe "`crystal env`" do
  it "prints all env vars" do
    Process.capture_result(crystal, "env")
      .should(be_success)
      .output
      .should(contain "CRYSTAL_PATH=")
      .should(contain "CRYSTAL_LIBRARY_PATH=")
      .should(contain "CRYSTAL_CACHE_DIR=")
      .should(contain "CRYSTAL_VERSION=")
  end

  it "prints var" do
    Process.capture_result(crystal, "env", "CRYSTAL_VERSION")
      .should(be_success)
      .output.should(match(/^\d+\.\d+\.\d+(-dev)?$/))
  end

  it "prints var from ENV" do
    env = {"CRYSTAL_CACHE_DIR" => "foobarbaz", "IYI_CACHE_DIR" => nil}
    Process.capture_result(crystal, "env", "CRYSTAL_CACHE_DIR", env: env)
      .should(be_success)
      .output.should(eq("#{File.expand_path("foobarbaz")}\n"))
  end

  it "prefers IYI_CACHE_DIR over CRYSTAL_CACHE_DIR" do
    env = {"CRYSTAL_CACHE_DIR" => "other", "IYI_CACHE_DIR" => "foobarbaz"}
    Process.capture_result(crystal, "env", "CRYSTAL_CACHE_DIR", env: env)
      .should(be_success)
      .output.should(eq("#{File.expand_path("foobarbaz")}\n"))
  end

  it "prints multiple vars" do
    Process.capture_result(crystal, "env", "CRYSTAL_VERSION", "CRYSTAL_PATH")
      .should(be_success)
      .output.should(match(/^\d+\.\d+\.\d+(-dev)?\n(\.\/|\.\\)?lib[:;].*$/))
  end
end
