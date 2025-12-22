#include "../include/yaml2fpga.h"
#include <arpa/inet.h>

static int parse_bool(yaml_event_t* event, bool* value) {
    if (event->type == YAML_SCALAR_EVENT) {
        char* scalar = (char*)event->data.scalar.value;
        *value = (strcmp(scalar, "true") == 0 || strcmp(scalar, "1") == 0);
        return SUCCESS;
    }
    return ERR_YAML_PARSE;
}

static int parse_uint32(yaml_event_t* event, uint32_t* value) {
    if (event->type == YAML_SCALAR_EVENT) {
        *value = (uint32_t)strtoul((char*)event->data.scalar.value, NULL, 10);
        return SUCCESS;
    }
    return ERR_YAML_PARSE;
}

static int parse_string(yaml_event_t* event, char* dest, size_t max_len) {
    if (event->type == YAML_SCALAR_EVENT) {
        strncpy(dest, (char*)event->data.scalar.value, max_len - 1);
        dest[max_len - 1] = '\0';
        return SUCCESS;
    }
    return ERR_YAML_PARSE;
}

static int parse_connection(yaml_parser_t* parser, network_connection_t* conn) {
    yaml_event_t event;
    char key[64] = {0};
    
    memset(conn, 0, sizeof(network_connection_t));
    
    while (1) {
        if (!yaml_parser_parse(parser, &event)) {
            return ERR_YAML_PARSE;
        }
        
        if (event.type == YAML_MAPPING_END_EVENT) {
            yaml_event_delete(&event);
            break;
        }
        
        if (event.type == YAML_SCALAR_EVENT) {
            strncpy(key, (char*)event.data.scalar.value, sizeof(key) - 1);
            yaml_event_delete(&event);
            
            if (!yaml_parser_parse(parser, &event)) {
                return ERR_YAML_PARSE;
            }
            
            if (strcmp(key, "up") == 0) {
                bool temp_up = false;
                parse_bool(&event, &temp_up);
                conn->up = temp_up ? CONN_UP : CONN_DOWN;
            } else if (strcmp(key, "host_id") == 0) {
                parse_uint32(&event, &conn->host_id);
            } else if (strcmp(key, "my_ip") == 0) {
                parse_string(&event, conn->my_ip, MAX_IP_ADDR_LEN);
            } else if (strcmp(key, "my_mac") == 0) {
                parse_string(&event, conn->my_mac, MAX_MAC_ADDR_LEN);
            } else if (strcmp(key, "my_port") == 0) {
                parse_uint32(&event, (uint32_t*)&conn->my_port);
            } else if (strcmp(key, "my_qp") == 0) {
                parse_uint32(&event, (uint32_t*)&conn->my_qp);
            } else if (strcmp(key, "peer_ip") == 0) {
                parse_string(&event, conn->peer_ip, MAX_IP_ADDR_LEN);
            } else if (strcmp(key, "peer_mac") == 0) {
                parse_string(&event, conn->peer_mac, MAX_MAC_ADDR_LEN);
            } else if (strcmp(key, "peer_port") == 0) {
                parse_uint32(&event, (uint32_t*)&conn->peer_port);
            } else if (strcmp(key, "peer_qp") == 0) {
                parse_uint32(&event, (uint32_t*)&conn->peer_qp);
            }
        }
        
        yaml_event_delete(&event);
    }
    
    return SUCCESS;
}

static int parse_switch(yaml_parser_t* parser, switch_config_t* switch_cfg) {
    yaml_event_t event;
    char key[64] = {0};
    
    memset(switch_cfg, 0, sizeof(switch_config_t));
    
    while (1) {
        if (!yaml_parser_parse(parser, &event)) {
            return ERR_YAML_PARSE;
        }
        
        if (event.type == YAML_MAPPING_END_EVENT) {
            yaml_event_delete(&event);
            break;
        }
        
        if (event.type == YAML_SCALAR_EVENT) {
            strncpy(key, (char*)event.data.scalar.value, sizeof(key) - 1);
            yaml_event_delete(&event);
            
            if (!yaml_parser_parse(parser, &event)) {
                return ERR_YAML_PARSE;
            }
            
            if (strcmp(key, "id") == 0) {
                parse_uint32(&event, &switch_cfg->id);
            } else if (strcmp(key, "root") == 0) {
                parse_bool(&event, &switch_cfg->is_root);
            } else if (strcmp(key, "connections") == 0) {
                if (event.type == YAML_SEQUENCE_START_EVENT) {
                    yaml_event_delete(&event);
                    
                    while (1) {
                        if (!yaml_parser_parse(parser, &event)) {
                            return ERR_YAML_PARSE;
                        }
                        
                        if (event.type == YAML_SEQUENCE_END_EVENT) {
                            yaml_event_delete(&event);
                            break;
                        }
                        
                        if (event.type == YAML_MAPPING_START_EVENT) {
                            yaml_event_delete(&event);
                            
                            if (switch_cfg->connection_count >= MAX_CONNECTIONS_PER_SWITCH) {
                                return ERR_INVALID_CONFIG;
                            }
                            
                            parse_connection(parser, &switch_cfg->connections[switch_cfg->connection_count]);
                            switch_cfg->connection_count++;
                        } else {
                            yaml_event_delete(&event);
                        }
                    }
                }
            }
        } else {
            yaml_event_delete(&event);
        }
    }
    
    return SUCCESS;
}

int parse_yaml_topology(const char* filename, topology_config_t* config) {
    FILE* file = fopen(filename, "r");
    if (!file) {
        return ERR_FILE_NOT_FOUND;
    }
    
    yaml_parser_t parser;
    if (!yaml_parser_initialize(&parser)) {
        fclose(file);
        return ERR_YAML_PARSE;
    }
    
    yaml_parser_set_input_file(&parser, file);
    yaml_event_t event;
    char key[64] = {0};
    int result = SUCCESS;
    
    memset(config, 0, sizeof(topology_config_t));
    
    while (1) {
        if (!yaml_parser_parse(&parser, &event)) {
            result = ERR_YAML_PARSE;
            break;
        }
        
        if (event.type == YAML_STREAM_END_EVENT) {
            yaml_event_delete(&event);
            break;
        }
        
        if (event.type == YAML_SCALAR_EVENT) {
            strncpy(key, (char*)event.data.scalar.value, sizeof(key) - 1);
            yaml_event_delete(&event);
            
            if (strcmp(key, "switches") == 0) {
                if (!yaml_parser_parse(&parser, &event)) {
                    result = ERR_YAML_PARSE;
                    break;
                }
                
                if (event.type == YAML_SEQUENCE_START_EVENT) {
                    yaml_event_delete(&event);
                    
                    while (1) {
                        if (!yaml_parser_parse(&parser, &event)) {
                            result = ERR_YAML_PARSE;
                            break;
                        }
                        
                        if (event.type == YAML_SEQUENCE_END_EVENT) {
                            yaml_event_delete(&event);
                            break;
                        }
                        
                        if (event.type == YAML_MAPPING_START_EVENT) {
                            yaml_event_delete(&event);
                            
                            if (config->switch_count >= MAX_SWITCHES) {
                                result = ERR_INVALID_CONFIG;
                                break;
                            }
                            
                            parse_switch(&parser, &config->switches[config->switch_count]);
                            config->switch_count++;
                        } else {
                            yaml_event_delete(&event);
                        }
                    }
                }
            } else {
                yaml_event_delete(&event);
            }
        } else {
            yaml_event_delete(&event);
        }
    }
    
    yaml_parser_delete(&parser);
    fclose(file);
    
    return result;
}