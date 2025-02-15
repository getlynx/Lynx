#include <stdio.h>
#include <stdlib.h>

int main (int argc, char **argv) {



  FILE *file = fopen ("capacitor.sh", "r");

  if (file) {

    fclose(file);

  } else {

    system ("logger -p user.error -t lynx -s capacitor capacitor.sh not found");

    return 0;

  }



  if (argc == 1) {

    system ("logger -p user.error -t lynx -s capacitor no command line argument");

    return 0;

  }



  char command[256];

  snprintf(command, sizeof(command), "/root/capacitor.sh %d &", atoi (argv[1]));

  system (command);



  return 0;

}

// gcc capacitor.c -o capacitor 
