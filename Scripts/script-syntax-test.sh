#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash -n Scripts/*.sh

for script in Scripts/*.sh; do
  if [[ "$(sed -n '1p' "$script")" != "#!/usr/bin/env bash" ]]; then
    echo "$script must start with #!/usr/bin/env bash" >&2
    exit 1
  fi
  if ! grep -Fxq "set -euo pipefail" "$script"; then
    echo "$script must enable set -euo pipefail" >&2
    exit 1
  fi
done

if grep -Eq '="\$\(grep .*\|.*head' Scripts/*.sh; then
  echo "Scripts/*.sh must not assign grep pipelines under set -euo pipefail" >&2
  exit 1
fi
