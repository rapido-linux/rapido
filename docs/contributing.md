# Contributing to Rapido

Contributions are welcome as pull requests or issue tickets against
[https://github.com/rapido-linux/rapido](https://github.com/rapido-linux/rapido).
They can alternatively be sent via email to any of the Git release taggers.


# Signing

## Developer Certificate of Origin

All commits must carry a `Signed-off-by` tag (git commit -s), acknowledging
that the contribution is made in accordance with the
[Developer Certificate of Origin](https://developercertificate.org/).


## Git Tags or Commits

Release tags must carry a GPG signature made with a trusted key (such as one
carried in https://git.kernel.org/pub/scm/docs/kernel/pgpkeys.git). E.g.
`git tag --sign ...`

Maintainers should avoid trusting Github for merge commits, etc. Instead, they
should ensure that branch HEAD remains signed by a trusted key. E.g.
`git merge --no-ff -S <changes_to_merge>`

Contributers are encouraged to GPG sign the HEAD commit of any branches
submitted via GitHub pull requests. E.g.
`git commit -S ...`. Non-HEAD commits needn't be GPG signed.


# Coding Style

Rapido uses style guidelines very similar to blktests:

- Indent with tabs.
- Don't add a space before the parentheses or a newline before the curly brace
  in function definitions.
- Variables set and used by the testing framework are in caps with underscores.
  E.g., TEST_NAME and GROUPS. Variables local to a test are lowercase
  with underscores.
- Functions should have a leading underscore.
- Use the bash [[ ]] form of tests instead of [ ].
- Always quote variable expansions unless the variable is a number or inside of
  a [[ ]] test.
- Use the $() form of command substitution instead of backticks.
- Use bash for loops instead of seq. E.g., for ((i = 0; i < 10; i++)), not
  for i in $(seq 0 9).
