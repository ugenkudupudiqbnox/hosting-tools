sudo ufw default deny incoming

sudo ufw default allow outgoing

sudo ufw limit ssh

sudo ufw allow OpenSSH

sudo ufw allow "Apache Secure"

sudo ufw show added

sudo ufw enable
