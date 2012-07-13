#!/bin/bash
#Author : Hemanth H.M
#Modifier : Francesco Fiore
#Licence : GNU GPLv3

# Usage
show_help(){
  echo "Usage is $0 -a|-m|-n|-c|-d|-l|-h -C count -I interval -D /path/to/output/directory"
  echo "-a or --all to plot cpu(c),mem(m),net(n),disk(d) and load(l)"
}

# Make directory to store the results
setdir(){
  mkdir -p $directory
  cd $directory
}

# Use dstat to get the data set
gendata(){
  echo "Collecting stats for ${count} count with an interval of ${interval} sec"
  
  dstat -tcnmdls --output dstat.csv $interval $count | tee dstat.dat
  [ "$?" -ne 0 ] && echo "Please check if you have installed dstat" && exit 1
  
  wait
  exec 2>/dev/null
  
  kill $! >/dev/null 2>&1
  #Remove the headers
  sed '/^"/ D; /^$/ D; s/,/ /g' dstat.csv > stat.dat
}

#############################################
# MAIN BLOCK
#############################################
# Use GNU plot to plot the graph
graph () {
gnuplot << EOF
set terminal $fileType
set output $output
set title $title
set xlabel $xlabel
set xdata time
set ylabel $ylabel
set timefmt "%d-%m %H:%M:%S "
set format x "%H:%M:%S"
set xtics rotate autofreq
plot ${plot[*]}
EOF
}

# Plot CPU usage
plotcpu(){
  fileType="png"
  output='"cpu.png"'
  title='"CPU usage"'
  xlabel='"time"'
  ylabel='"percent"'

  plot=( '"stat.dat"' using 1:3 title '"user"' with lines,'"stat.dat"' using 1:4 title '"system"' with lines,'"stat.dat"' using 1:5 title '"idle"' with lines,'"stat.dat"' using 1:6 title '"wait"' with lines )

  graph

}

# Plot memory usage
plotmem(){
  fileType="png"
  output='"memory.png"'
  title='"Memory usage"'
  xlabel='"time"'
  ylabel='"size(MB)"'

  plot=( '"stat.dat"' using 1:\(\$11/1000000\) title '"used"' with lines,'"stat.dat"' using 1:\(\$12/1000000\) title '"buff"' with lines, '"stat.dat"' using 1:\(\$13/1000000\) title '"cach"' with lines,'"stat.dat"' using 1:\(\$14/1000000\) title '"free"' with lines )

  graph
}

# Plot network usage
plotnet(){
  fileType="png"
  output='"network.png"'
  title='"Network usage"'
  xlabel='"time"'
  ylabel='"size(KB)"'

  plot=( '"stat.dat"' using 1:\(\$9/1000\) title '"recv"' with lines,'"stat.dat"' using 1:\(\$10/1000\) title '"send"' with lines )

  graph

}

# Plot disk usage
plotdisk(){
  fileType="png"
  output='"disk.png"'
  title='"Disk usage"'
  xlabel='"time"'
  ylabel='"size(KB)"'

  plot=( '"stat.dat"' using 1:\(\$15/1000\) title '"read"' with lines,'"stat.dat"' using 1:\(\$16/1000\) title '"writ"' with lines )

  graph

}

# Plot load average
plotload(){
  fileType="png"
  output='"load.png"'
  title='"Load average"'
  xlabel='"time"'
  ylabel='"load"'

  plot=( '"stat.dat"' using 1:17 title '"1m"' with lines,'"stat.dat"' using 1:18 title '"5m"' with lines,'"stat.dat"' using 1:19 title '"15m"' with lines )

  graph

}

# Plot swap usage
plotswap(){
  fileType="png"
  output='"swap.png"'
  title='"Swap usage"'
  xlabel='"time"'
  ylabel='"size(MB)"'

  plot=( '"stat.dat"' using 1:\(\$20/1000000\) title '"used"' with lines,'"stat.dat"' using 1:\(\$21/1000000\) title '"free"' with lines )

  graph

}

# Clean up all the collected stats
clean(){
  echo "Cleaning"
  cd Stats
  rm -r *.dat
  echo "Done!"
}

# Loop for different options
while getopts "hamncdlsC:I:D:" opt; do
  case "$opt" in
    h) show_help; exit 0;;
    a) args=$args"mncdls" ;;
    m) args=$args"m" ;;
    n) args=$args"n" ;;
    c) args=$args"c" ;;
    d) args=$args"d" ;;
    l) args=$args"l" ;;
    s) args=$args"s" ;;
    C) count=$OPTARG ;;
    I) interval=$OPTARG ;;
    D) directory=$OPTARG ;;
    ?) echo "invalid arguments"; show_help; exit 1;;
  esac
done

if [[ -z $args ]] || [[ -z $count ]] || [[ -z $interval ]] || [[ -z $directory ]]; then
  echo "missing arguments"
  show_help
  exit 1
fi

# Set dir and gen data
setdir
gendata

# Plot results
echo "Plot results into '$directory' directory"
echo $args | grep -q "m" --
[ "$?" -eq 0 ] && plotmem
  
echo $args | grep -q "n" --
[ "$?" -eq 0 ] && plotnet
  
echo $args | grep -q "c" --
[ "$?" -eq 0 ] && plotcpu
  
echo $args | grep -q "d" --
[ "$?" -eq 0 ] && plotdisk
  
echo $args | grep -q "l" --
[ "$?" -eq 0 ] && plotload

echo $args | grep -q "s" --
[ "$?" -eq 0 ] && plotswap
  
exit 0