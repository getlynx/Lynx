#include <stdio.h>
#include <stdlib.h>

int main (int argc, char **argv) {

  char command[256];

  snprintf(command, sizeof(command), "/root/capacitor.sh %d &", atoi (argv[1]));

  system (command);

  return 0;

}

// gcc capacitor.c -o capacitor 
