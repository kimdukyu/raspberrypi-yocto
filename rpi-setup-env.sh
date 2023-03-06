#!/bin/sh

MACHINE=raspberrypi4-64
setup_j=4
setup_t=2

#
# parse the parameters
#
OLDOPTION=$OPTION
while getopts "m:j:t:lh" setup_flag
do
	case $setup_flag in
		m) MACHINE="$OPTARG";
			;;
        j) setup_j="$OPTARG";
           ;;
        t) setup_t="$OPTARG";
           ;;
		l) setup_l='true';
			;;
		h) setup_h='true';
			;;
		?) setup_error='true';
			;;
	esac
done
OPTION=$OLDOPTION

#
# Set build env
#
PROGNAME="rpi-setup-env.sh"
#ROOTDIR="`readlink -f $0 | xargs dirname`"
ROOTDIR=`pwd -P`
SOURCESDIR="sources"

OEROOTDIR=${ROOTDIR}/${SOURCESDIR}/poky
if [ -e ${ROOTDIR}/${SOURCESDIR}/oe-core ]; then
	OEROOTDIR=${ROOTDIR}/${SOURCESDIR}/oe-core
fi

FSLROOTDIR=${ROOTDIR}/${SOURCESDIR}/meta-raspberrypi
PROJECT_DIR=${ROOTDIR}/build_${MACHINE}

LAYER_LIST=" \
	meta-openembedded/meta-oe \
	meta-openembedded/meta-python \
	meta-openembedded/meta-networking \
	meta-openembedded/meta-multimedia \
	meta-raspberrypi \
"

prompt_message()
{
local i=''
echo "Welcome to Raspberrypi Auto Linux BSP (Reference Distro)

The Yocto Project has extensive documentation about OE including a
reference manual which can be found at:
    http://yoctoproject.org/documentation

For more information about OpenEmbedded see their website:
    http://www.openembedded.org/

You can now run 'bitbake <target>'
"
    echo "Targets specific to raspberrypi:"
    for layer in $(echo $LAYER_LIST | xargs); do
        rpi_recipes=$(find ${ROOTDIR}/${SOURCESDIR}/$layer -path "*recipes-*/images/rpi*.bb" -or -path "images/rpi*.bb" 2> /dev/null)
        if [ -n "$rpi_recipes" ]
        then
            for i in $(echo $rpi_recipes | xargs);do
                i=$(basename $i);
                i=$(echo $i | sed -e 's,^\(.*\)\.bb,\1,' 2> /dev/null)
                echo "    $i";
            done
        fi
    done

	echo ""
    echo "To return to this build environment later please run:"
    echo "    . $PROJECT_DIR/SOURCE_THIS"
}

clean_up()
{
	unset OLDOPTION MACHINE setup_l setup_h setup_error OPTION \
		  PROGNAME ROOTDIR SOURCESDIR OEROOTDIR PROJECT_DIR LAYER_LIST

	unset -f usage prompt_message
}

usage()
{
	ls $FSLROOTDIR/conf/machine/*.conf

    if [ $? -eq 0 ]; then
        echo -n -e "\n    Supported machines: "
        for layer in $(eval echo $USAGE_LIST); do
            if [ -d ${ROOTDIR}/${SOURCESDIR}/${layer}/conf/machine ]; then
                echo -n -e "`ls ${ROOTDIR}/${SOURCESDIR}/${layer}/conf/machine | grep "\.conf" \
                   | egrep -v "^${MACHINEEXCLUSION}" | sed s/\.conf//g | xargs echo` "
            fi
        done
        echo ""
    else
        echo "    ERROR: no available machine conf file is found. "
    fi

    echo "    Optional parameters:
    * [-m machine]: the target machine to be built.
    * [-j jobs]:    number of jobs for make to spawn during the compilation stage.
    * [-t tasks]:   number of BitBake tasks that can be issued in parallel.
    * [-l]:         lite mode. To help conserve disk space, deletes the building
                    directory once the package is built.
    * [-h]:         help
"
    if [ "`readlink $SHELL`" = "dash" ];then
        echo "
    You are using dash which does not pass args when being sourced.
    To workaround this limitation, use \"set -- args\" prior to
    sourcing this script. For exmaple:
        \$ set -- -m raspberrypi4-64 -j 4 -t 2
        \$ . $ROOTDIR/$PROGNAME
"
    fi

	echo ""
	echo "Usage: . $PROGNAME -m <machine> -j 4 -t 2"
	echo "       ex) $PROGNAME -m raspberrypi4-64 -j 4 -t 2"
}

# check if project folder was created before
if [ -e "$PROJECT_DIR/SOURCE_THIS" ]; then
    echo "$PROJECT_DIR was created before."
    . $PROJECT_DIR/SOURCE_THIS
    echo "Nothing is changed."
    clean_up && return
fi


# check the "-h" and other not supported options
if test $setup_error || test $setup_h; then
    usage && clean_up && return
fi


unset DISTRO
if [ -n "$distro_override" ]; then
    DISTRO="$distro_override";
fi

if [ -z "$DISTRO" ]; then
    DISTRO="$DEFAULT_DISTRO"
fi

# Check the machine type specified
# Note that we intentionally do not test ${MACHINEEXCLUSION}
unset MACHINELAYER
if [ -n "${MACHINE}" ]; then
    for layer in $(eval echo $LAYER_LIST); do
		echo ${ROOTDIR}/${SOURCESDIR}/${layer}
        if [ -e ${ROOTDIR}/${SOURCESDIR}/${layer}/conf/machine/${MACHINE}.conf ]; then
            MACHINELAYER="${ROOTDIR}/${SOURCESDIR}/${layer}"
            break
        fi
    done
else
    usage && clean_up && return $EINVAL
fi

if [ -n "${MACHINELAYER}" ]; then 
    echo "Configuring for ${MACHINE} and distro ${DISTRO}..."
else
    echo -e "\nThe \$MACHINE you have specified ($MACHINE) is not supported by this build setup."
    usage && clean_up && return $EINVAL
fi


# set default jobs and threads
CPUS=`grep -c processor /proc/cpuinfo`
JOBS="$(( ${CPUS} * 3 / 2))"
THREADS="$(( ${CPUS} * 2 ))"

# check optional jobs and threads
if echo "$setup_j" | egrep -q "^[0-9]+$"; then
    JOBS=$setup_j
fi
if echo "$setup_t" | egrep -q "^[0-9]+$"; then
    THREADS=$setup_t
fi

# set project folder location and name
if [ -n "$setup_builddir" ]; then
    if echo $setup_builddir |grep -q ^/;then
        PROJECT_DIR="${setup_builddir}"
    else
        PROJECT_DIR="`pwd`/${setup_builddir}"
    fi
else
    PROJECT_DIR=${ROOTDIR}/build_${MACHINE}
fi
mkdir -p $PROJECT_DIR

# check if project folder was created before
if [ -e "$PROJECT_DIR/SOURCE_THIS" ]; then
    echo "$PROJECT_DIR was created before."
    . $PROJECT_DIR/SOURCE_THIS
    echo "Nothing is changed."
    clean_up && return
fi

# source oe-init-build-env to init build env
cd $OEROOTDIR
set -- $PROJECT_DIR
. ./oe-init-build-env > /dev/null

# add layers
for layer in $(eval echo $LAYER_LIST); do
    append_layer=""
    if [ -e ${ROOTDIR}/${SOURCESDIR}/${layer} ]; then
        append_layer="${ROOTDIR}/${SOURCESDIR}/${layer}"
    fi
    if [ -n "${append_layer}" ]; then
        append_layer=`readlink -f $append_layer`
        awk '/  "/ && !x {print "'"  ${append_layer}"' \\"; x=1} 1' \
            conf/bblayers.conf > conf/bblayers.conf~
        mv conf/bblayers.conf~ conf/bblayers.conf

        # check if layer is compatible with supported yocto version.
        # if not, make it so.
        conffile_path="${append_layer}/conf/layer.conf"
        yocto_compatible=`grep "LAYERSERIES_COMPAT" "${conffile_path}" | grep "${YOCTOVERSION}"`
        if [ -z "${yocto_compatible}" ]; then
		    sed -E "/LAYERSERIES_COMPAT/s/(\".*)\"/\1 $YOCTOVERSION\"/g" -i "${conffile_path}"
		    echo Layer ${layer} updated for ${YOCTOVERSION}.
		fi
    fi
done

# if conf/local.conf not generated, no need to go further
if [ ! -e conf/local.conf ]; then
    echo "ERROR: the local.conf is not created, Exit ..."
    clean_up && cd $ROOTDIR && return
fi

# Remove comment lines and empty lines
sed -i -e '/^#.*/d' -e '/^$/d' conf/local.conf

# Change settings according to the environment
sed -e "s,MACHINE ??=.*,MACHINE ??= '$MACHINE',g" -i conf/local.conf

# Input command
echo "ENABLE_UART=\"1\"" >> conf/local.conf

prompt_message
cd ${PROJECT_DIR}
clean_up

