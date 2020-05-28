"""Provides go_yacc and genfile_check_test

Copyright 2016 Google Inc. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
"""

load(
    "@io_bazel_rules_go//go/private:providers.bzl",
    "GoSource",
)

_GO_YACC_TOOL = "@org_golang_x_tools//cmd/goyacc"

def _go_yacc_impl(ctx):
    args = ctx.actions.args()
    args.add("-o", ctx.outputs.out)
    args.add(ctx.file.src)
    goroot = "%s/.." % ctx.executable._go_yacc_tool.dirname
    ctx.actions.run(
        executable = ctx.executable._go_yacc_tool,
        arguments = [args],
        inputs = [ctx.file.src],
        outputs = [ctx.outputs.out],
        env = {
            "GOROOT": goroot,
        },
    )
    return DefaultInfo(
        files = depset([ctx.outputs.out]),
    )

_go_yacc = rule(
    implementation = _go_yacc_impl,
    attrs = {
        "src": attr.label(
            allow_single_file = True,
        ),
        "out": attr.output(),
        "_go_yacc_tool": attr.label(
            default = _GO_YACC_TOOL,
            allow_single_file = True,
            executable = True,
            cfg = "host",
        ),
    },
)

"""Runs go tool yacc -o $out $src."""
def go_yacc(src, out, visibility = None):
    _go_yacc(
        name = src + ".go_yacc",
        src = src,
        out = out,
        visibility = visibility,
    )

def _extract_go_src(ctx):
    """Thin rule that exposes the GoSource from a go_library."""
    return [DefaultInfo(files = depset(ctx.attr.library[GoSource].srcs))]

extract_go_src = rule(
    implementation = _extract_go_src,
    attrs = {
        "library": attr.label(
            providers = [GoSource],
        ),
    },
)

def genfile_check_test(src, gen):
    """Asserts that any checked-in generated code matches bazel gen."""
    if not src:
        fail("src is required", "src")
    if not gen:
        fail("gen is required", "gen")
    native.genrule(
        name = src + "_checksh",
        outs = [src + "_check.sh"],
        cmd = r"""cat >$@ <<'eof'
#!/bin/bash
# Script generated by @com_github_bazelbuild_buildtools//build:build_defs.bzl

# --- begin runfiles.bash initialization ---
# Copy-pasted from Bazel's Bash runfiles library (tools/bash/runfiles/runfiles.bash).
set -euo pipefail
if [[ ! -d "$${RUNFILES_DIR:-/dev/null}" && ! -f "$${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  if [[ -f "$$0.runfiles_manifest" ]]; then
    export RUNFILES_MANIFEST_FILE="$$0.runfiles_manifest"
  elif [[ -f "$$0.runfiles/MANIFEST" ]]; then
    export RUNFILES_MANIFEST_FILE="$$0.runfiles/MANIFEST"
  elif [[ -f "$$0.runfiles/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
    export RUNFILES_DIR="$$0.runfiles"
  fi
fi
if [[ -f "$${RUNFILES_DIR:-/dev/null}/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
  source "$${RUNFILES_DIR}/bazel_tools/tools/bash/runfiles/runfiles.bash"
elif [[ -f "$${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  source "$$(grep -m1 "^bazel_tools/tools/bash/runfiles/runfiles.bash " \
            "$$RUNFILES_MANIFEST_FILE" | cut -d ' ' -f 2-)"
else
  echo >&2 "ERROR: cannot find @bazel_tools//tools/bash/runfiles:runfiles.bash"
  exit 1
fi
# --- end runfiles.bash initialization ---

[[ "$$1" = external/* ]] && F1="$${1#external/}" || F1="$$TEST_WORKSPACE/$$1"
[[ "$$2" = external/* ]] && F2="$${2#external/}" || F2="$$TEST_WORKSPACE/$$2"
F1="$$(rlocation "$$F1")"
F2="$$(rlocation "$$F2")"
diff -q "$$F1" "$$F2"
eof
""",
    )
    native.sh_test(
        name = src + "_checkshtest",
        size = "small",
        srcs = [src + "_check.sh"],
        deps = ["@bazel_tools//tools/bash/runfiles"],
        data = [src, gen],
        args = ["$(location " + src + ")", "$(location " + gen + ")"],
    )

    # magic copy rule used to update the checked-in version
    native.genrule(
        name = src + "_copysh",
        srcs = [gen],
        outs = [src + "copy.sh"],
        cmd = "echo 'cp $${BUILD_WORKSPACE_DIRECTORY}/$(location " + gen +
              ") $${BUILD_WORKSPACE_DIRECTORY}/" + native.package_name() + "/" + src + "' > $@",
    )
    native.sh_binary(
        name = src + "_copy",
        srcs = [src + "_copysh"],
        data = [gen],
    )

def go_proto_checkedin_test(src, proto = "go_default_library"):
    """Asserts that any checked-in .pb.go code matches bazel gen."""
    genfile = src + "_genfile"
    extract_go_src(
        name = genfile + "go",
        library = proto,
    )

    # TODO(pmbethe09): why is the extra copy needed?
    native.genrule(
        name = genfile,
        srcs = [genfile + "go"],
        outs = [genfile + ".go"],
        cmd = "cp $< $@",
    )
    genfile_check_test(src, genfile)
