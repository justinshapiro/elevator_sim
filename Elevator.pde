class Elevator {
  public int location;
  public int direction;
  public int speed;
  public int stopTime;
  public int designation_num;
  public boolean sort_reverse;
  public boolean full;
  public boolean stopped;
 
  public Vector<Person> passengers = new Vector<Person>(MAX_ELEVATOR_CAPACITY); 
  public ArrayList<Integer> future_event = new ArrayList<Integer>(); // sorted by increasing destinations
  
  Elevator() {
    location = 0;
    direction = 0;
    stopped = true;
    full = false;
    sort_reverse = false;
    speed = 1;
    stopTime = 5;
    designation_num = 0;
  }
  
  public int getDirection() {
    int direction = 0;
    if (future_event.isEmpty()) // direction is always up for an elevator at floor 0
      direction = 0;
    else if (location - future_event.get(0) != 0)
      direction = (future_event.get(0) - location)/(abs(location-future_event.get(0)));
    else {
      direction = 0;
      stopped = true;
    }
    return direction;
  }
  
  public int getPersonDirection(Person p, int loc) {
    int p_dir = 0;
    if ((p.dest - loc) != 0)
      p_dir = (p.dest - loc)/(abs(loc-p.dest));
    return p_dir;
  }
  
  public boolean isFull() {
    if (passengers.size() == MAX_ELEVATOR_CAPACITY)
      full = true;
    else
      full = false;
    return full;
  }
  
  public int getLocation(){
    return location;
  }
  
  public int getPassengers(){
    return passengers.size();
  }
  
  public boolean[] getPassType(){
   boolean[] passType = new boolean[passengers.size()];
   for (int i = 0; i < passengers.size(); i ++){
     passType[i] = passengers.get(i).type; 
   }
   return passType;
  }
  
  public void move() {
    if (!stopped){
      _DEBUG("Elevator #" + designation_num + " is moving");
      
      int dir = getDirection(); // -1 for down, 0 for stopped, 1 for up
      location += dir*speed;
    }
    else if (stopped && stopTime > 0) {
      _DEBUG("Elevator #" + designation_num + " is stopped at floor " + location);
      
      fill_elevator();
      if (stopTime > 0) 
        stopTime--;
    }
    else if (stopped && stopTime == 0){
      _DEBUG("Elevator #" + designation_num + " is closing its doors");
      
      if (future_event.size() > 0)
        stopped = false;
      else if (passengers.size() < 1) {
        future_event.add(new Integer(0));
        //sortEvents();
      }
      stopTime = 5;
    }
  }
  
  public void fill_elevator() {
    // first, process departing passengers  
    if (passengers.size() > 0) {
      boolean fullfillment = false;
      
      _DEBUG("Elevator #" + designation_num + " :: fill_elevator() started step 1");
      
      for (int i = 0; i < passengers.size(); i++) {
        if (location == passengers.get(i).dest) {
          fullfillment = true;
          if (location > 0) 
            SCHEDULE_FLOOR_QUEUE(passengers.get(i), location);
          STATS.gather_trip_length(current_sim_time() - passengers.get(i).trip_start_time);
          passengers.remove(i);
          future_event.remove(new Integer(location));
          sortEvents();          
          _DEBUG(" !!!! " + location + " removed from Elevator #" + designation_num + "'s event-list");
        }
      }
      if (!fullfillment) {
        future_event.remove(new Integer(location)); // phantom button press, real-world-like
        
        _DEBUG(" !!!! " + location + " removed from Elevator #" + designation_num + "'s event-list");
      }
    }
    else if (passengers.isEmpty() && ELEVATOR_REQUEST_QUEUE.get(location).isEmpty()) {
      future_event.remove(new Integer(location));
      _DEBUG(" !!!! " + location + " removed from Elevator #" + designation_num + "'s event-list");
    }
        
    // second, actually fill the elevator
    if (stopped == true) {
      _DEBUG("Elevator #" + designation_num + " :: fill_elevator() started step 2");
      
      if (ELEVATOR_REQUEST_QUEUE.get(location).size() > 0) {
        for (int i = 0; i < ELEVATOR_REQUEST_QUEUE.get(location).size(); i++) {
          Person p = ELEVATOR_REQUEST_QUEUE.get(location).get(i);
          if (passengers.size() < MAX_ELEVATOR_CAPACITY && (getPersonDirection(p, location)*direction) >= 0) {
            STATS.gather_wait_times(p.queue_arrival_time);
            p.queue_arrival_time = 0;
            passengers.add(p);
            p.trip_start_time = current_sim_time();
            ELEVATOR_REQUEST_QUEUE.get(location).remove(p);
            _DEBUG("Person with destination " + p.dest + " loaded onto Elevator #" + designation_num);
            
            if (!future_event.contains(p.dest)) {
              future_event.add(p.dest);
              sortEvents();
            }
          }
          else {
            cont.request_elevator(location, getPersonDirection(p, location));
          }
        }
      }
      if (stopTime == 0) {
        stopped = false;
      }
    }
  }
  
  public void sortEvents() {
    int dir = getDirection();
    ArrayList backward_event = new ArrayList();
    Collections.sort(future_event);
    if (dir == -1)
      Collections.reverse(future_event);
    for (int i = 0; i < future_event.size(); i++) { 
      if (((future_event.get(i) - location) * dir) < 0) {
        backward_event.add(future_event.get(i));
        future_event.remove(i);
      }
      Collections.sort(backward_event);
      Collections.reverse(backward_event);
    }
    future_event.addAll(backward_event);
  }
  
  public void SCHEDULE_FLOOR_QUEUE(final Person p, final int current_floor) {   
    final ScheduledThreadPoolExecutor queue_add = new ScheduledThreadPoolExecutor(5);
    queue_add.schedule (new Runnable () {
      @Override 
      public void run() {
            // Determine if next destination is non-zero
    if (p.single_trip && current_sim_time() < DAY_LENGTH) {
        p.dest = floor(random(MAX_FLOORS - 1));
        while (p.dest == current_floor)
          p.dest = floor(random(MAX_FLOORS - 1));
        p.idle_time = floor(random(DAY_LENGTH - current_sim_time()));
        p.queue_arrival_time = 0;
      }
      else {
        p.dest = 0;
        p.single_trip = false;
        p.idle_time = floor(random(5000));
    }
        ELEVATOR_REQUEST_QUEUE.get(current_floor).add(p);
        p.queue_arrival_time = current_sim_time();
        Elevator temp = cont.request_elevator(current_floor, getPersonDirection(p, current_floor));
        _DEBUG("Person with destination " + p.dest + " has requested Elevator #" + temp.designation_num + " from floor " + current_floor);
        
        // Print the Elevator-Request-Queue for floor(location)
        if (__DEBUG__) {
          print("Person-Destination-List for ERQ" + location + " is: ");
          if (ELEVATOR_REQUEST_QUEUE.get(location).isEmpty())
            print("EMPTY");
          else {
            for (int i = 0; i < ELEVATOR_REQUEST_QUEUE.get(location).size(); i++) 
              print(ELEVATOR_REQUEST_QUEUE.get(location).get(i).dest + " ");
          }  
          _DEBUG(" ");
        }
      }  
    }, p.idle_time, TimeUnit.MILLISECONDS);
  }
}