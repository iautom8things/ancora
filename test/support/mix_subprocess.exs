defmodule Ancora.MixSubprocess do
  @moduledoc false

  def run(args) when is_list(args) do
    real_mix = System.find_executable("mix")
    wrapper_dir = Path.join(System.tmp_dir!(), "ancora-mix-#{System.unique_integer([:positive])}")
    stderr_path = Path.join(wrapper_dir, "stderr")
    wrapper = Path.join(wrapper_dir, "mix")
    File.mkdir_p!(wrapper_dir)

    File.write!(wrapper, "#!/bin/sh\nexec #{real_mix} \"$@\" 2>\"$ANCORA_STDERR_FILE\"\n")
    File.chmod!(wrapper, 0o755)

    {stdout, status} =
      System.cmd(wrapper, args,
        cd: File.cwd!(),
        env: [{"ANCORA_STDERR_FILE", stderr_path}]
      )

    stderr = File.read!(stderr_path)
    File.rm_rf!(wrapper_dir)
    %{stdout: stdout, stderr: stderr, status: status}
  end
end
