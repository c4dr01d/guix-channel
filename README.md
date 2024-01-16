# Guix channel
My personal guix channel

## Usage
This channel can be installed as a Guix channel, add it to `~/.config/guix/channels.scm` or `/etc/guix/channels.scm`:

``` scheme
(cons* (channel
        (name 'c4dr01d-guix)
	(url "https://github.com/c4dr01d/guix-channel"))
       %default-channels)
```

Then run `guix pull`.