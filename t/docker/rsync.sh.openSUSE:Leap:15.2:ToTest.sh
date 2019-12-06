#!lib/test-in-container-systemd.sh

set -ex

su $dbuser -c 'set -ex
cd /opt/openqa-trigger-from-obs
mkdir -p openSUSE:Leap:15.2:ToTest
python3 script/scriptgen.py openSUSE:Leap:15.2:ToTest
[ ! -e openSUSE:Leap:15.2:ToTest/.run_last ] || rm openSUSE:Leap:15.2:ToTest/.run_last
echo geekotest > rsync.secret'

echo '127.0.0.1 obspublish' >> /etc/hosts
systemctl enable --now postgresql

su postgres -c "createuser -D $dbuser"
su postgres -c "createdb -O $dbuser $dbname"


systemctl enable --now apache2.service
systemctl enable --now openqa-webui.service
systemctl enable --now openqa-websockets.service
# scheduler and livehandler are not needed in this test
# systemctl enable --now openqa-scheduler.service
# systemctl enable --now openqa-livehandler.service
systemctl enable --now openqa-gru.service

# wait for webui to become available
sleep 2
attempts_left=10
while ! curl -sI http://localhost/ | grep 200 ; do
    sleep 3
    : $((attempts_left--))
    [ "$attempts_left" -gt 0 ] || {
        service openqa-webui status
        exit 1
    }
done

# this must create default user
curl -sI http://localhost/login

# create api key - the table will be available after webui service startup
API_KEY=$(hexdump -n 8 -e '2/4 "%08X" 1 "\n"' /dev/urandom)
API_SECRET=$(hexdump -n 8 -e '2/4 "%08X" 1 "\n"' /dev/urandom)
echo "INSERT INTO api_keys (key, secret, user_id, t_created, t_updated) VALUES ('${API_KEY}', '${API_SECRET}', 2, NOW(), NOW());" | su postgres -c "psql $dbname"

cat >> /etc/openqa/client.conf <<EOF
[localhost]
key = ${API_KEY}
secret = ${API_SECRET}
EOF

mkdir -p /var/lib/openqa/.config/openqa/
cp /etc/openqa/client.conf /var/lib/openqa/.config/openqa/
chown "$dbuser" /var/lib/openqa/.config/openqa/client.conf

systemctl enable --now rsyncd

su "$dbuser" -c '/opt/openqa-trigger-from-obs/script/rsync.sh openSUSE:Leap:15.2:ToTest'

sleep 10
set -x
# make sure run did happen
test -f /var/lib/openqa/factory/iso/openSUSE-Leap-15.2-DVD-x86_64-Build519.3-Media.iso
test -f /var/lib/openqa/factory/iso/openSUSE-Leap-15.2-NET-x86_64-Build519.3-Media.iso
test -d /var/lib/openqa/factory/repo/openSUSE-15.2-oss-i586-x86_64-Build519.3
test -d /var/lib/openqa/factory/repo/openSUSE-15.2-oss-i586-x86_64-Build519.3-source
test -f /var/lib/openqa/factory/repo/openSUSE-15.2-oss-i586-x86_64-Build519.3-source/src/coreutils
test ! -f /var/lib/openqa/factory/repo/openSUSE-15.2-oss-i586-x86_64-Build519.3-source/src/other
test -d /var/lib/openqa/factory/repo/openSUSE-15.2-oss-i586-x86_64-Build519.3-debuginfo
test -d /var/lib/openqa/factory/repo/openSUSE-15.2-oss-i586-x86_64-Build519.3-debuginfo/x86_64
test -f /var/lib/openqa/factory/repo/openSUSE-15.2-oss-i586-x86_64-Build519.3-debuginfo/x86_64/mraa-debug
test ! -f /var/lib/openqa/factory/repo/openSUSE-15.2-oss-i586-x86_64-Build519.3-debuginfo/x86_64/other
test -z "$(ls -lRa /var/lib/openqa/factory/repo/ | grep other)"
test -d /var/lib/openqa/factory/repo/openSUSE-15.2-non-oss-i586-x86_64-Build519.3
test ! -d /var/lib/openqa/factory/repo/openSUSE-15.2-non-oss-i586-x86_64-Build519.3-source
test ! -d /var/lib/openqa/factory/repo/openSUSE-15.2-non-oss-i586-x86_64-Build519.3-debuginfo

test -f /opt/openqa-trigger-from-obs/openSUSE:Leap:15.2:ToTest/.run_last/openqa.cmd.log
grep -q 'scheduled_product_id => 1' /opt/openqa-trigger-from-obs/openSUSE:Leap:15.2:ToTest/.run_last/openqa.cmd.log

echo PASS ${BASH_SOURCE[0]}
