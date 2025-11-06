sudo -u www-data -- wp db reset --yes --url="https://pressbook.braou.ac.in"
if [[ $? -ne 0 ]] ; then
        exit 1;
fi

sudo -u www-data -- wp core multisite-install --url="https://pressbook.braou.ac.in" --title="Dr. B.R. AMBEDKAR OPEN UNIVERSITY" --admin_user="admin" --admin_password="ixGmgMPXeBcS0gqBoWtd2g==" --admin_email="ugen@qbnox.com"
if [[ $? -ne 0 ]] ; then
        exit 1;
fi

sudo -u www-data -- wp plugin activate pressbooks --network --url="https://pressbook.braou.ac.in"
if [[ $? -ne 0 ]] ; then
        exit 1;
fi
