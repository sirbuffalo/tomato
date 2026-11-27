# tier: any
# `tomato config [FILE]` and the two files it reads: the project's tomato.toml (the nearest one, from FILE's folder or the current folder
# upward) and the user's config.toml in $TOMATO_HOME (default ~/.tomato). The text shows each setting and where it came from.
. "$CONTRACT_DIR/lib.sh"

P="$W/proj"; mkdir -p "$P/sub/deep" "$TOMATO_HOME"
here="$(cd "$P" && pwd -P)"
try "config: no files, the built-in defaults" 0 @config_defaults.txt "" config
within "$P" try "config in a folder with no file: the same" 0 @config_defaults.txt "" config
within "$P" try "config FILE with no file near it: the same" 0 @config_defaults.txt "" config sub/deep/x.tom
try "config: a FILE in a folder that does not exist is looked up as far as it can" 0 @config_defaults.txt "" config nosuchfolder/x.tom
try "config: --color=never is accepted" 0 @config_defaults.txt "" config --color=never
try "config: two words are a usage error" 2 "" @help.txt config a.tom b.tom

# a project file: the nearest one upward, found from the folder of FILE or the current folder
printf '[project]\nname = "demo"\nversion = "0.3.0"\ntomato = "%s"\n\n[limits]\nexp_bits = 2048\nformat_digits = 1_000\n' "$minv" > "$P/tomato.toml"
within "$P" try "config: a project file: its settings, and name, version and the Tomato it needs" 0 @config_project.txt "" config
within "$P" try "config FILE: the nearest tomato.toml is found from a parent folder" 0 @config_project.txt "" config sub/deep/x.tom
within "$P/sub/deep" try "config: found from a subfolder of the project" 0 @config_project.txt "" config
try "config FILE given as a path from elsewhere" 0 @config_project.txt "" config "$P/sub/deep/x.tom"
printf '[project]\nname = "demo"\nversion = "0.3.0"\ntomato = "%s"\n\n[build]\nmode = "release"\noutput = "out/app"\n[build.crash]\nmode = "debug"\n' "$minv" > "$P/tomato.toml"
within "$P" try "config shows the [build] table (not [build.ENTRY])" 0 @config_build.txt "" config

# the user's file, and the project's file over it, setting by setting
printf '[limits]\nexp_bits = 4096\nformat_digits = 7000\n' > "$TOMATO_HOME/config.toml"
rm -f "$P/tomato.toml"
within "$P" try "config: the user's file alone" 0 @config_user.txt "" config
printf '# a seed manifest\n[seed]\nname = "a.example/x"\nversion = "1.0.0"\ntomato = "%s"\n\n[limits]\nformat_digits = 9000\n\n[build]\nmode = "release"\n' "$minv" > "$P/sub/tomato.toml"
within "$P" try "config: the project's setting wins over the user's, the others stay; a seed is named, its [build] is ignored" 0 @config_seed.txt "" config sub/deep/x.tom
rm -f "$P/sub/tomato.toml" "$TOMATO_HOME/config.toml"

# mistakes in the files are errors with an id, naming the file, status 1, on standard error (config reports them as run and build do)
bad_file() { # NAME FILE-TEXT WHERE(project|user) MESSAGE-OR-~PREFIX
  if [ "$3" = user ]; then f="$TOMATO_HOME/config.toml"; else f="$P/tomato.toml"; fi
  printf '%s' "$2" > "$f"
  within "$P" try "config: $1" 1 "" "$4" config
  rm -f "$f"
}
bad_file "a limit below what a double reaches" '[limits]
exp_bits = 100
' project "error[E543]: $here/tomato.toml: limits.exp_bits must be a whole number from 2048 to 2147483647, not 100"
bad_file "a limit above what the runtime can build" '[limits]
format_digits = 2147483648
' project "error[E543]: $here/tomato.toml: limits.format_digits must be a whole number from 1000 to 2147483647, not 2147483648"
bad_file "a limit that is not a number" '[limits]
format_digits = "many"
' project "error[E543]: $here/tomato.toml: limits.format_digits must be a whole number from 1000 to 2147483647, not \"many\""
bad_file "an unknown limit" '[limits]
exp_bit = 5000
' project "error[E542]: $here/tomato.toml: unknown setting limits.exp_bit (the settings are exp_bits and format_digits)"
bad_file "limits that is not a table" 'limits = 5
' project "error[E541]: $here/tomato.toml: limits must be a table ([limits]), not an integer"
bad_file "text that is not TOML names the file" '[limits
' project "~error[E540]: the configuration file $here/tomato.toml is not valid TOML: "
bad_file "a bad limit in the user's file names that file" '[limits]
exp_bits = 5
' user "error[E543]: $TOMATO_HOME/config.toml: limits.exp_bits must be a whole number from 2048 to 2147483647, not 5"
# a manifest that needs a newer Tomato: config shows what it needs and is not an error; running a program of the project is (E562)
printf '[project]\nname = "x"\nversion = "0.1.0"\ntomato = "99.0"\n' > "$P/tomato.toml"
printf '@main\ndef main():\n    print(1)\n' > "$P/sub/p.tom"
within "$P" try "config shows the Tomato a project needs, even a newer one" 0 "~project: x 0.1.0 (needs Tomato 99.0 or newer)" "" config
within "$P" try "run refuses a project that needs a newer Tomato, and says how to get it" 1 "" "error[E562]: $here/tomato.toml: this needs Tomato 99.0 or newer, and this is Tomato $version
  = help: install a newer release with \`tomato update\`" run sub/p.tom

# the user's [build] mode is shown, and says it is only a default
printf '[build]\nmode = "release"\n' > "$TOMATO_HOME/config.toml"
within "$P" try "config shows the user's [build] mode and where it ranks" 0 @config_user_build.txt "" config
rm -f "$TOMATO_HOME/config.toml"
