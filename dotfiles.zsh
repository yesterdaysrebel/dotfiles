# Installed by github.com/yesterdaysrebel/dotfiles into ~/.oh-my-zsh/custom/.
# Oh-My-Zsh sources custom/*.zsh after its own plugins, so this turns on the pinned
# zsh plugins without editing ~/.zshrc. Delete this file to opt out.
() {
  local dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins" name
  # zsh-syntax-highlighting must load last.
  for name in zsh-autosuggestions you-should-use zsh-syntax-highlighting; do
    (( ${+plugins} )) && (( ${plugins[(Ie)$name]} )) && continue   # already in plugins=()
    [[ -r "$dir/$name/$name.plugin.zsh" ]] && source "$dir/$name/$name.plugin.zsh"
  done
  return 0
}
