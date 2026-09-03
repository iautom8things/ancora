defmodule Ancora.SourceScanTest do
  use ExUnit.Case, async: true

  alias Ancora.SourceScan

  @tag :tmp_dir
  @tag spec: "ancora.source_scan.declarative_config"
  test "scans directories and globs while excluding allowlisted files", %{tmp_dir: root} do
    # Would fail if scan/1 skipped directory expansion, glob expansion, either
    # token form, line numbers, or the path allowlist.
    nested = Path.join([root, "lib", "nested"])
    File.mkdir_p!(nested)
    direct = Path.join(root, "lib/direct.ex")
    globbed = Path.join(nested, "globbed.ex")
    allowed = Path.join(nested, "allowed.ex")
    File.write!(direct, "System.cmd(\"git\", [])\n")
    File.write!(globbed, "safe()\n:os.cmd('date')\n")
    File.write!(allowed, "System.cmd(\"allowed\", [])\n")

    assert SourceScan.scan(
             dirs_or_globs: [Path.join(root, "lib"), Path.join(nested, "*.ex")],
             tokens: ["System.cmd", ~r/:os\.cmd/],
             allowlist: [allowed]
           ) == [
             {direct, 1, "System.cmd"},
             {globbed, 2, ~r/:os\.cmd/}
           ]
  end

  @tag :tmp_dir
  @tag spec: "ancora.source_scan.vacuity_guard"
  test "raises when no files remain to scan", %{tmp_dir: root} do
    # Would fail if scan/1 returned an empty violation list for an empty file set.
    only_file = Path.join(root, "only.ex")
    File.write!(only_file, "safe()\n")

    assert_raise ArgumentError, "source scan resolved to zero files", fn ->
      SourceScan.scan(
        dirs_or_globs: [Path.join(root, "missing/**/*.ex"), only_file],
        tokens: ["System.cmd"],
        allowlist: [only_file]
      )
    end
  end

  @tag :tmp_dir
  @tag spec: "ancora.source_scan.whole_token_matching"
  test "plain strings match whole tokens while regexes remain verbatim", %{tmp_dir: root} do
    # Would fail if scan/1 treated plain strings as substrings or wrapped a caller's regex.
    source = Path.join(root, "bindings.ex")
    File.write!(source, "system_cmd = :safe\ncmd = :violation\n")

    assert SourceScan.scan(
             dirs_or_globs: [source],
             tokens: ["cmd", ~r/cmd/],
             allowlist: []
           ) == [
             {source, 1, ~r/cmd/},
             {source, 2, "cmd"},
             {source, 2, ~r/cmd/}
           ]
  end

  @tag :tmp_dir
  @tag spec: "ancora.source_scan.no_execution"
  test "scans through file reads without process-spawning calls", %{tmp_dir: root} do
    # Would fail if the production module gained a shell or port-spawning call.
    source = Path.join(root, "safe.ex")
    File.write!(source, "safe()\n")

    assert SourceScan.scan(dirs_or_globs: [source], tokens: ["System.cmd"], allowlist: []) == []

    module_source = File.read!(Path.expand("../../lib/ancora/source_scan.ex", __DIR__))
    refute module_source =~ "System." <> "cmd"
    refute module_source =~ "System." <> "shell"
    refute module_source =~ "Port." <> "open"
    refute module_source =~ ":os." <> "cmd"
  end
end
