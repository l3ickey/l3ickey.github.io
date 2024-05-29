---
layout: post
title: Settig Up a GOAD Environment on a Windows Host
subtitle: ペンテスターの遊び場
tags: [active directory, goad]
---

## Game of Active Directory (GOAD)

[GOAD](https://github.com/Orange-Cyberdefense/GOAD) はペンテスト用の Active Directory ラボプロジェクトです。このラボの目的は、ペンテスターに一般的な攻撃手法を練習するための脆弱な Active Directory 環境を提供することです。

[GOAD に含まれている脆弱性](https://github.com/Orange-Cyberdefense/GOAD?tab=readme-ov-file#road-map)は 2024/05/30 現在で45個あり、例として PTH, Zerologon, Kerberoasting, Ntlm relay, Constrained delegation などがあります。

GOAD プロジェクトには4種類のラボ環境があり、それぞれの構成は以下の通りです。

- GOAD：5つのVM（2フォレスト、3ドメイン）から成る完全な GOAD ラボ
- GOAD-Light：3つのVM（1フォレスト、2ドメイン）かる成る小規模 PC 向けのライト GOAD ラボ
- SCCM：4つのVM（1フォレスト、1ドメイン）から成る Microsoft Configuration Manager がインストール済みのラボ
- NHA：5つのVM（2ドメイン）から成るスキーマが提供されていないチャレンジラボ

私は複数フォレスト環境で遊んでみたかったので、今回は GOAD ラボを選択しました。

## Windows ホストで GOAD ラボを構築

[GOAD の Requirements](https://github.com/Orange-Cyberdefense/GOAD?tab=readme-ov-file#requirements) を確認すると、Linux ホスト環境でしかテストされていない旨が書かれています。

> The lab intend to be installed from a **Linux host** and was tested only on this.

しかし、Windows ホスト環境でも GOAD ラボの構築に成功している人がおり、公式リポジトリにも [Windows ホストで GOAD ラボを構築する方法](https://github.com/Orange-Cyberdefense/GOAD/blob/main/docs/install_with_vmware_Windows.md)がまとめられています。

公式リポジトリはテキストのみの簡素な手順であるため、この記事にスクリーンショットやエラー対処を含む詳細な手順をまとめます。GOAD ラボ構築の参考になれば幸いです。

### 検証環境

- Host OS: Windows 11 Home (23H2)
  - CPU: AMD Ryzen 9 3900XT
  - RAM: 64GB
  - VMware Workstation 16 Pro
  - Vagrant: 2.4.1
    - Vagrant VMware Utility: 1.0.22

  - Vagrant Plugin
    - vagrant-vmware-desktop: 3.0.3
    - vagrant-reload: 0.0.1

- Ubuntu VM: 22.04.4 LTS
  - Python: 3.10.12
  - pip: 24.0
    - ansible-core: 2.12.6
    - pywinrm: 0.4.3

- GOAD: [606d9cd](https://github.com/Orange-Cyberdefense/GOAD/tree/606d9cd9895d53cd36489b47196e20ed07d8a33c)

RAM は GOAD ラボのみを動かすのであれば 32GB で足りると思いますが、他のアプリも同時に起動したい場合は 64GB あると良さそうです。

ディスクスペースは Vagrant boxes が 47.3GB、Ubuntu VM が 27.5GB、GOAD VM が 47.0GB で合計 121.8GB 消費していました。スナップショットを撮るとさらに消費するため、200GB 程度用意しておくと安心です。

### Vagrant で GOAD VM を作成

まず初めに [Vagrant](https://developer.hashicorp.com/vagrant/install), [Vagrant VMware Utility](https://developer.hashicorp.com/vagrant/install/vmware) をダウンロードし、インストールします。

Vagrant のインストールが完了したら、Vagrant Plugin をインストールします。

```powershell
vagrant plugin install vagrant-vmware-desktop
```

```powershell
vagrant plugin install vagrant-reload
```

プラグインがインストールされていることを確認します。

```powershell
vagrant plugin list
```

![image-20240530022110868](https://l3ickey.github.io/assets/img/typora-images/image-20240530022110868.png){: .mx-auto.d-block :}

次に [GOAD リポジトリ](https://github.com/Orange-Cyberdefense/GOAD)をクローンまたは zip でダウンロードします。

zip の場合は展開し、Vagrantfile が置いてあるディレクトリまで移動します。（GOAD 以外のラボを構築する場合はパスを適宜読み替えてください。）

```powershell
cd .\GOAD-main\ad\GOAD\providers\vmware\
```

vagrant のバージョンが 2.2.19 より大きい場合、vagrant up でエラーが発生してしまうため Vagrantfile に次の2行を追記します。

```
config.winrm.transport = "plaintext"
config.winrm.basic_auth_only = true
```

![image-20240530040007172](https://l3ickey.github.io/assets/img/typora-images/image-20240530040007172.png){: .mx-auto.d-block :}

vagrant up コマンドで VM を作成する。

```powershell
vagrant up
```

![image-20240530024304717](https://l3ickey.github.io/assets/img/typora-images/image-20240530024304717.png){: .mx-auto.d-block :}

{: .box-note}
**Note:** ラボ構築で発生する場合は [Troubleshooting](https://github.com/Orange-Cyberdefense/GOAD/blob/main/docs/troubleshoot.md) を確認すると解決法が見つかるかもしれません。

全ての VM が作成されたら VMware から 編集 > 仮想ネットワーク エディタ... を開き、サブネットアドレスが 192.168.56.0 になっている仮想ネットワークの名前をメモしておきます。

![image-20240530033402726](https://l3ickey.github.io/assets/img/typora-images/image-20240530033402726.png){: .mx-auto.d-block :}

### Ubuntu VM を作成

ここで作成する Ubuntu VM は1つ前の手順で作成した GOAD VM に Ansible でプロビジョニングを行うための環境です。

[Ubuntu 22.04.4 TLS](https://releases.ubuntu.com/jammy/) の iso ファイルをダウンロードします。

VMware から ホーム > 新規仮想マシンの作成 を開き、構成のタイプで カスタム を選択します。

![image-20240530040945622](https://l3ickey.github.io/assets/img/typora-images/image-20240530040945622.png){: .mx-auto.d-block :}

インストーラディスクイメージファイルにダウンロードした iso ファイルを選択します。Linux のユーザー名やパスワード、仮想マシン名、メモリ、CPUはPCのスペックと相談しながら適当に決めます。私の環境ではメモリ 16GB、CPU 8プロセッサを割り当てました。

![image-20240530041444830](https://l3ickey.github.io/assets/img/typora-images/image-20240530041444830.png){: .mx-auto.d-block :}

Ubuntu のインストーラーが起動したら指示に従って Ubuntu をインストールします。Ansible が動けば良いので Minimal Ubuntu を選択しました。

Ubuntu のインストールが完了したら、VMware からUbuntu 22.04.4 LTS を右クリックし、設定... > ハードウェア > 追加... > ネットワークアダプタ > 完了 でネットワークアダプタを追加します。追加したネットワークアダプタは カスタム を選択し、メモした GOAD ラボの仮想ネットワークを指定します。

![image-20240530042942706](https://l3ickey.github.io/assets/img/typora-images/image-20240530042942706.png){: .mx-auto.d-block :}

ネットワークアダプタが追加されたら Ubuntu の設定を開き、Network > 歯車アイコン > IPv4 からIPアドレスを割り当てます。この際に GOAD VM とIPアドレスが被っていないことを確認してください。

![image-20240530043719917](https://l3ickey.github.io/assets/img/typora-images/image-20240530043719917.png){: .mx-auto.d-block :}

ネットワークに繋がったら Ubuntu VM と GOAD VM の間で疎通確認をします。

Ubuntu VM 側で ICMP パケットをキャプチャします。

```bash
sudo tcpdump -i ens36 icmp
```

GOAD-DC01 の Vagrant ユーザーにパスワード vagrant でログインし、PowerShell で Ubuntu VM に ping を実行します。

```powershell
ping 192.168.56.129
```

![image-20240530044759336](https://l3ickey.github.io/assets/img/typora-images/image-20240530044759336.png){: .mx-auto.d-block :}

Ubuntu VM で ICMP パケットを受信していれば成功です。

![image-20240530044941882](https://l3ickey.github.io/assets/img/typora-images/image-20240530044941882.png){: .mx-auto.d-block :}

### Ansible を使ったプロビジョニング

Ubuntu VM にプロビジョニングに必要なパッケージをインストールします。

```bash
sudo apt update
sudo apt install python3-pip sshpass lftp rsync openssh-client

pip install --upgrade pip
pip install ansible-core==2.12.6
pip install pywinrm

git clone https://github.com/Orange-Cyberdefense/GOAD
cd GOAD/ansible
ansible-galaxy install -y requirements.yml
```

{: .box-warning}
**Warning:** Python は 3.8 以上、ansible-core は 2.12.6 である必要があります。

goad.sh を使ってプロビジョニングを実行します。私の環境ではビルドが完了するまでに79分55秒掛かりました。気長に待ちましょう☕

```bash
cd ../
./goad.sh -t install -l GOAD -p vmware -m local -a
```

![image-20240529105435969](https://l3ickey.github.io/assets/img/typora-images/image-20240529105435969.png){: .mx-auto.d-block :}

エラーが発生した場合は [Troubleshooting](https://github.com/Orange-Cyberdefense/GOAD/blob/main/docs/troubleshoot.md) などでエラーを解決し、エラーが発生しなくなるまで goad.sh を実行します。下記のコマンドのように特定のプロビジョニングのみを行うことも可能です。

```bash
ansible-playbook -i ../ad/GOAD/data/inventory -i ../ad/GOAD/providers/vmware/inventory ad-child_domain.yml
```

プロビジョニングが完了したら NetExec を使って GOAD ラボ環境のIPアドレス、マシン名、ドメイン名を取得してみます。

```bash
nxc smb 192.168.56.0/24
```

![image-20240529211656238](https://l3ickey.github.io/assets/img/typora-images/image-20240529211656238.png){: .mx-auto.d-block :}

これで GOAD ラボの構築は完了です！ラボを楽しみましょう！

ちなみに GOAD で使用している Windows Server は180日間の無料期間が過ぎると使えなくなってしまいます。各サーバーにライセンスを入力するか、ラボを再構築することで対処する必要があるのでご注意ください。
