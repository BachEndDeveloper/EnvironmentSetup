# Setup for verified commits

To Setup verified commits using SSH keys:

Create SSH key:

```script
ssh-keygen -t ed25519 -C "you@email.com"
```

Add the SSH key to the SSH-Agent

```script
/usr/bin/ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

Copy the public key to the clipboard:

```script
pbcopy < ~/.ssh/id_ed25519.pub
```

Add the public key to GitHub in the profile settings, as a signing key
[Documentation on GitHub](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits)

Configure GIT:

```script
git config --global commit.gpgsign true
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519
```
