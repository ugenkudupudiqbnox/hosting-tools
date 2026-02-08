#!/bin/sh
#
# Written by: Ugendreshwar Kudupudi (connect@qbnox.com)
#
# Last updated on : 27th July, 2021
#
# MIT License (MIT)
# 
# Copyright (c) 2021 Qbnox Systems Private Limited (lms.qbnox.com)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

timestamp=`date +%d%m%y%H%M%S`

cnf=/home/ubuntu/moodlebackup/my.cnf

# specify the backup directory home
backupdir=$(awk '/^backupdir/ {split($0, a, "="); gsub(/^[ \t]+|[ \t]+$/, "", a[2]); print a[2]; exit}' $cnf)

# moodle home dir
mhome=$(awk '/^mhome/ {split($0, a, "="); gsub(/^[ \t]+|[ \t]+$/, "", a[2]); print a[2]; exit}' $cnf)

# moodle upload dir
muploaddir=$(awk '/^muploaddir/ {split($0, a, "="); gsub(/^[ \t]+|[ \t]+$/, "", a[2]); print a[2]; exit}' $cnf)

# moodle database name
dbname=$(awk '/^database/ {split($0, a, "="); gsub(/^[ \t]+|[ \t]+$/, "", a[2]); print a[2]; exit}' $cnf)

# default dir name
backupdir=$backupdir/'moodle_'$timestamp

spinner()
{
    local pid=$!
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

exec_prereq()
{
	# create the backup dir if not available
	if [ ! -d $backupdir ] ; then
		mkdir -p $backupdir
		if [ $? -ne 0 ] ;  then
			echo 1
		else
			cd $backupdir
		fi
	fi
}

exec_step1n2()
{
	# Step 1 and 2: backup moodle software and moodle upload directory
	tar zcfP moodle_sw_n_data_$timestamp.tgz $mhome $muploaddir
	if [ $? -ne 0 ] ; then
		echo 1
	fi
}

exec_step3()
{
	# Step 3: backup database
	mysqldump --defaults-extra-file=${cnf} --no-tablespaces --single-transaction -C -Q -e --create-options ${dbname} > moodle-database.sql
	if [ $? -ne 0 ] ; then
		echo 1
	fi

	tar zcf moodle_db_$timestamp.tgz moodle-database.sql
	if [ $? -ne 0 ] ; then
		echo 1
	else
		rm moodle-database.sql
	fi
}

exec_welcome_msg()
{
	clear
	echo
	echo
	echo "\t\t Welcome to Qbnox Systems Moodle Backup Services"
	echo
	echo
	echo "Creating backup files with timestamp" $timestamp
	echo 

}

exec_exit_msg()
{
	echo "Please find all back files in "$backupdir
	echo 
	ls $backupdir
	echo 
	echo "Looking for Moodle Hosting? "
	echo 
	echo "Call or WhatsApp Us: +91 90085 11933 or e-mail connect@qbnox.com"
	echo 
	echo 
}

exec_welcome_msg

exec_prereq

printf "Backing up Moodle software and data files... " 
(exec_step1n2) & spinner
printf "Done"
echo 
echo 

printf "Backing up Moodle Database... " 
(exec_step3) & spinner
printf "Done"
echo
echo 


exec_exit_msg
