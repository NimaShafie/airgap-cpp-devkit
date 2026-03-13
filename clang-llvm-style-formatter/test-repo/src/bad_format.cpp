#include <vector>
#include <string>

int main( ){std::vector<std::string> values={"a","b","c"};for(auto & value:values){if(value.size()>0){value="x";}}return 0;}
