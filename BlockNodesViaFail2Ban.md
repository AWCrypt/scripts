# Block IPs from other nodes that are not upgraded to the latest node version and on the allegra mainnet

If you have already installed **fail2ban** to ban bad actors trying to break into your machine, good, if not

``` console
$ sudo apt-get update
$ sudo apt-get install fail2ban
``` 

## Just two simple files are needed for the config

**/etc/fail2ban/jail.d/cardano.conf**
``` console
# service name
[cardano]
# turn on /off
enabled  = true
# ports to ban (numeric or text)
port     = 3001
# filter file
filter   = cardano
# file to parse
logpath  = /home/username/cardano/logs/relay.json
# ban rule:
# 3 times in 3 minutes
maxretry = 3
findtime = 180
# ban for 1 day
bantime = 86400
```

Adjust the path/port so it is in line with your Relay Node setup.

**/etc/fail2ban/filter.d/cardano.conf**
``` console
[Definition]
failregex = ^.*HardForkEncoderDisabledEra.*"address":"<HOST>:.*$
```

The logfile for the Relay Node must be in **JSON mode** for this regex expression to work!

So make sure your config file for the Relay has something like this in:
``` console
.
.
.
"defaultScribes": [
    [
      "StdoutSK",
      "stdout"
    ],
    [
            "FileSK",
            "/home/username/cardano/logs/relay.json"
    ]
  ],
.
.
.
"setupScribes": [
    {
      "scFormat": "ScJson",
      "scKind": "FileSK",
      "scName": "/home/username/cardano/logs/relay.json",
      "scRotation": null
    }
  ]
.
.
.
```

## Restart fail2ban

Now you only have to restart your fail2ban service like:
``` console
$ sudo systemctl restart fail2ban
```

And if you have such Nodes you should see them getting banned away pretty soon like:
``` console
$ sudo fail2ban-client status cardano

Status for the jail: cardano
|- Filter
|  |- Currently failed: 0
|  |- Total failed:     2
|  `- File list:        /home/username/cardano/logs/relay.json
`- Actions
   |- Currently banned: 9
   |- Total banned:     9
   `- Banned IP list:   128.199.14.115 138.197.165.16 164.90.228.228 167.71.254.148 178.157.82.189 194.99.21.198 3.96.104.103 51.89.164.212 95.217.221.117
```

This should improve the stability of your Relay Node until a new cardano-node version fixes this automatically.

Best regards, Martin - ATADA Stakepool Austria
