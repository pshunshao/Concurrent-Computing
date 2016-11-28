// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 16                  //image height
#define  IMWD 16                  //image width
#define  WRKRS 6                  //number of worker threads

typedef unsigned char uchar;      //using uchar as shorthand for an unsigned character
//commented out as apparently this type is defined somewhere else
//typedef unsigned int uint;        //using unint as shorthand for an unsigned integer
typedef unsigned char ubyte;      //using uchar as shorthand for an unsigned byte

port p_scl = XS1_PORT_1E;         //interface ports to orientation
port p_sda = XS1_PORT_1F;

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6

//total number of worker threads
const uint NUMBER_OF_WORKERS = WRKRS;
//the height of the grid
const uint GRID_HEIGHT = IMHT;
//width of the grid
const uint GRID_WIDTH = IMWD;
//value of an alive cell
const ubyte ALIVE_CELL = 1;
//value of a dead cell
const ubyte DEAD_CELL = 0;

/*
 * interface for communication between workers
 */
interface WorkerWorker {
    /*
     * Returns 1 if the cell at the given column
     * in the top row is alive and 0 otherwise
     */
    ubyte getTopRowCell(uint column);

    /*
     * Returns 1 if the cell at the given column
     * in the bottom row is alive and 0 otherwise
     */
    ubyte getBottomRowCell(uint column);
};

/*
 * Interface for communication between a distributor and a worker
 */
interface DistributorWorker {
    /*
     * Initialises the subgrid of the worker by allocating
     * space able to hold data for rowCount*columnCount cells
     */
    void initialiseSubgrid(uint rowCount, uint columnCount);

    /*
     * Sets the initial value of cell at the given row and column
     * of the worker's subgrid to cellValue
     */
    void initialiseCell(ubyte cellValue, uint row, uint column);

    /*
     * Start computing next generation of cells of the game
     */
    void runEvolution();

    /*
     * Return the value in the worker's subgrid
     * from the current generation at the given row and column
     */
    ubyte getCurrentGenerationCell(uint row, uint column);

    /*
     * Get the number of rows in the worker's subgrid
     */
    uint getSubgridHeight();

    /*
     * Get the number of columns in the worker's subgrid
     */
     uint getSubgridWidth();
};

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], chanend c_out)
{
  int res;
  uchar line[ IMWD ];
  printf( "DataInStream: Start...\n" );

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT );
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }

  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    _readinline( line, IMWD );
    for( int x = 0; x < IMWD; x++ ) {
      c_out <: line[ x ];
      printf( "-%4.1d ", line[ x ] ); //show image values
    }
    printf( "\n" );
  }

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream: Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////

/*
 * Get the worker index working on the given row index number
 */
ubyte getWorkerForRow(uint row) {
    //avoiding potential overflow and making the function more flexible
    row = row % GRID_HEIGHT;

    //all workers will get at least this number of rows to work with
    uint baseNumberOfRowsPerWorker = GRID_HEIGHT / NUMBER_OF_WORKERS;

    //finding the remainder of rows. First extraRows number of workers will get one extra row to work with
    //in order to distribute the rows as evenly as possible
    uint extraRows = GRID_HEIGHT % NUMBER_OF_WORKERS;

    //now the logic for computing which worker the current row belongs to:
    //find the last row for a woker working with an extra row
    uint lastExtraRowIndex = extraRows * (baseNumberOfRowsPerWorker + 1) - 1; //-1 since it's 0-based

    ubyte workerIndex = -1;
    if(row <= lastExtraRowIndex) {
        //row belongs to one of the first workers with an extra row to work with
        workerIndex = row / (baseNumberOfRowsPerWorker + 1);
    } else {
        //row belongs to one of the rest of workers with base number of rows to work with
        workerIndex = (row - lastExtraRowIndex - 1) / baseNumberOfRowsPerWorker + extraRows;
    }
    return workerIndex;
}

//void worker()

//distributes the grid workload to the worker threads
void distributor(chanend gridInputChannel, chanend gridOutputChannel, chanend accelerometerInputChannel)
{

    printf("Distributor started. Let the evolution games begin!\n");

    printf("Initialising worker threads...\n");


    printf("Starting to read input image with height: %d and width: %d\n", GRID_HEIGHT, GRID_WIDTH);
    for(int row = 0; row < GRID_HEIGHT; ++row) {
        for(int column = 0; column < GRID_WIDTH; ++column) {
            uchar currentCellValue;
            gridInputChannel :> currentCellValue;  //read the current pixel value
            ubyte cellState = (currentCellValue == 255) ? ALIVE_CELL : DEAD_CELL;
            printf("%d", cellState);
        }
    }

  printf( "\nOne processing round completed...\n" );
}
/*
void distributor(chanend c_in, chanend c_out, chanend fromAcc)
{
  uchar val;

  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
  printf( "Waiting for Board Tilt...\n" );
  //fromAcc :> int value;

  //Read in and do something with your image values..
  //This just inverts every pixel, but you should
  //change the image according to the "Game of Life"
  printf( "Processing...\n" );
  for( int y = 0; y < IMHT; y++ ) {   //go through all lines
    for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
      c_in :> val;                    //read the pixel value
      c_out <: (uchar)( val ^ 0xFF ); //send some modified pixel out
    }
  }
  printf( "\nOne processing round completed...\n" );
}
*/

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in)
{
  int res;
  uchar line[ IMWD ];

  //Open PGM file
  printf( "DataOutStream: Start...\n" );
  res = _openoutpgm( outfname, IMWD, IMHT );
  if( res ) {
    printf( "DataOutStream: Error opening %s\n.", outfname );
    return;
  }

  //Compile each line of the image and write the image line-by-line
  for( int y = 0; y < IMHT; y++ ) {
    for( int x = 0; x < IMWD; x++ ) {
      c_in :> line[ x ];
    }
    _writeoutline( line, IMWD );
    printf( "DataOutStream: Line written...\n" );
  }

  //Close the PGM image
  _closeoutpgm();
  printf( "DataOutStream: Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read orientation, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void orientation( client interface i2c_master_if i2c, chanend toDist) {
  i2c_regop_res_t result;
  char status_data = 0;
  int tilted = 0;

  // Configure FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }
  
  // Enable FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  //Probe the orientation x-axis forever
  while (1) {

    //check until new orientation data is available
    do {
      status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
    } while (!status_data & 0x08);

    //get new x-axis tilt value
    int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

    //send signal to distributor after first tilt
    if (!tilted) {
      if (x>30) {
        tilted = 1 - tilted;
        toDist <: 1;
      }
    }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {

i2c_master_if i2c[1];               //interface to orientation

char infname[] = "test.pgm";     //put your input image path here
char outfname[] = "testout.pgm"; //put your output image path here
chan c_inIO, c_outIO, c_control;    //extend your channel definitions here

par {
    i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    orientation(i2c[0],c_control);        //client thread reading orientation data
    DataInStream(infname, c_inIO);          //thread to read in a PGM image
    DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
    distributor(c_inIO, c_outIO, c_control);//thread to coordinate work on image
  }

  return 0;
}
