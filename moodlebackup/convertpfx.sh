
# this script converts PFX file to PEM

outfile=certificate.pem

if [[ x$1 = x ]] ; then
file=BraouPRTKEY.pfx
else
file=$1
fi
openssl pkcs12 -in $file -out $outfile -clcerts

if [[ $? -eq 0 ]] ; then
cat $outfile
fi
