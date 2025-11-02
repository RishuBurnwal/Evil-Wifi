#!/usr/bin/env python3

import pyshark
import sys
import os

def extract_cookies(pcap_file, output_file):
    """Extract cookies from HTTP packets in a pcap file"""
    cookies = []
    
    # Ensure output directory exists
    output_dir = os.path.dirname(output_file)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    try:
        # Create capture object with HTTP filter
        capture = pyshark.FileCapture(pcap_file, display_filter='http')
        
        print(f"Processing {pcap_file}...")
        
        for packet in capture:
            try:
                # Look for HTTP cookies in requests
                if hasattr(packet, 'http'):
                    # Check for cookie in request headers
                    if hasattr(packet.http, 'cookie'):
                        cookies.append(packet.http.cookie)
                    # Check for set-cookie in response headers
                    elif hasattr(packet.http, 'set_cookie'):
                        cookies.append(packet.http.set_cookie)
            except AttributeError:
                # Skip packets without HTTP layer
                continue
            except Exception as e:
                # Skip packets with other errors
                print(f"Warning: Skipping packet due to error: {e}")
                continue
        
        capture.close()
        
        # Write cookies to output file
        with open(output_file, 'w') as f:
            for cookie in cookies:
                f.write(cookie + '\n')
        
        print(f"Extracted {len(cookies)} cookies and saved to {output_file}")
        return len(cookies)
        
    except Exception as e:
        print(f"Error processing pcap file: {e}")
        return 0

def extract_credentials(pcap_file, output_file):
    """Extract potential credentials from HTTP packets"""
    credentials = []
    
    # Ensure output directory exists
    output_dir = os.path.dirname(output_file)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    try:
        # Create capture object with HTTP filter
        capture = pyshark.FileCapture(pcap_file, display_filter='http')
        
        print(f"Processing {pcap_file} for credentials...")
        
        for packet in capture:
            try:
                # Look for HTTP form data that might contain credentials
                if hasattr(packet, 'http'):
                    # Check for form data in POST requests
                    if hasattr(packet.http, 'file_data'):
                        data = packet.http.file_data
                        # Look for common credential fields
                        if any(keyword in data.lower() for keyword in ['password', 'username', 'user', 'pass', 'email']):
                            credentials.append(data)
            except AttributeError:
                # Skip packets without HTTP layer
                continue
            except Exception as e:
                # Skip packets with other errors
                print(f"Warning: Skipping packet due to error: {e}")
                continue
        
        capture.close()
        
        # Write credentials to output file
        with open(output_file, 'w') as f:
            for credential in credentials:
                f.write(credential + '\n')
        
        print(f"Extracted {len(credentials)} potential credentials and saved to {output_file}")
        return len(credentials)
        
    except Exception as e:
        print(f"Error processing pcap file for credentials: {e}")
        return 0

def extract_urls(pcap_file, output_file):
    """Extract visited URLs from HTTP packets"""
    urls = []
    
    # Ensure output directory exists
    output_dir = os.path.dirname(output_file)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    try:
        # Create capture object with HTTP filter
        capture = pyshark.FileCapture(pcap_file, display_filter='http')
        
        print(f"Processing {pcap_file} for URLs...")
        
        for packet in capture:
            try:
                # Look for HTTP requests
                if hasattr(packet, 'http'):
                    # Check for host and path in HTTP requests
                    if hasattr(packet.http, 'host') and hasattr(packet.http, 'request_uri'):
                        url = f"http://{packet.http.host}{packet.http.request_uri}"
                        if url not in urls:  # Avoid duplicates
                            urls.append(url)
                    elif hasattr(packet.http, 'host'):
                        url = f"http://{packet.http.host}/"
                        if url not in urls:  # Avoid duplicates
                            urls.append(url)
            except AttributeError:
                # Skip packets without HTTP layer
                continue
            except Exception as e:
                # Skip packets with other errors
                print(f"Warning: Skipping packet due to error: {e}")
                continue
        
        capture.close()
        
        # Write URLs to output file
        with open(output_file, 'w') as f:
            for url in urls:
                f.write(url + '\n')
        
        print(f"Extracted {len(urls)} unique URLs and saved to {output_file}")
        return len(urls)
        
    except Exception as e:
        print(f"Error processing pcap file for URLs: {e}")
        return 0

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 cookie_extractor.py <pcap_file>")
        sys.exit(1)
    
    pcap_file = sys.argv[1]
    
    if not os.path.exists(pcap_file):
        print(f"Error: File {pcap_file} not found")
        sys.exit(1)
    
    # Extract cookies
    cookies_count = extract_cookies(pcap_file, 'logs/cookies.txt')
    
    # Extract credentials
    credentials_count = extract_credentials(pcap_file, 'logs/credentials.txt')
    
    # Extract URLs
    urls_count = extract_urls(pcap_file, 'logs/urls.txt')
    
    print(f"Extraction complete: {cookies_count} cookies, {credentials_count} credentials, {urls_count} URLs found")