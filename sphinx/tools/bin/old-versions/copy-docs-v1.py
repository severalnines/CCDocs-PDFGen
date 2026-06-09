#!/usr/bin/env python3
"""
Script to copy docs directory with custom rules:
- Rename index.md to {parent-dir}.md
- Skip files/directories specified in ignore file
"""

import os
import shutil
import argparse
import configparser
import fnmatch
from pathlib import Path

class ConfigError(Exception):
    pass

def load_config(config_file='config.ini'):
    """Load configuration from INI file."""

    """ check if file exists first """
    if not os.path.exists(config_file):
        #raise ConfigError(f"Configuration file '{config_file}' not found or does not exists!")
        try:
            raise ConfigError(f"Configuration file '{config_file}' not found or does not exists!")
        except ConfigError as e:
            print(e)  # prints: something went wrong

    config = configparser.ConfigParser()
    config.read(config_file)
    return config


def load_ignore_patterns(ignore_file):
    """Load ignore patterns from external file."""
    patterns = []
    if not os.path.exists(ignore_file):
        ##print(f"Warning: Ignore file '{ignore_file}' not found. Proceeding without ignores.")
        ##return patterns
        #raise ConfigError(f"Ignore file configuration file '{ignore_file}' not found or does not exists!")  
        try:
            raise ConfigError(f"Ignore file configuration file '{ignore_file}' not found or does not exists!")
        except ConfigError as e:
            print(e)  # prints: something went wrong        
    
    with open(ignore_file, 'r') as f:
        for line in f:
            line = line.strip()
            # Skip empty lines and comments
            if line and not line.startswith('#'):
                patterns.append(line)
    
    return patterns


def should_ignore(src_file, source_dir, ignore_patterns):
    """Check if path should be ignored based on patterns."""
    src_file_str = str(src_file)
    #filename  = os.path.basename(path_str)
    dirname  = os.path.dirname(src_file)
    #compare_fname  = f"./" + src_file[len(source_dir):]
    compare_fname  = src_file[len(source_dir):]
    #print(f"[DEBUG] The ignore patterns filename should be [{filename}]")

    #print(f"[DEBUG] prefix|should_ignore->path_str is {path_str}")
    #print(f"[DEBUG] prefix|should_ignore->dirname is {dirname}")

    for pattern in ignore_patterns:
        #clean_pattern = pattern
        clean_pattern = pattern.rstrip('/')
        #clean_pattern = pattern.rstrip(source_dir)
        #path_strip_raw = f"./" + path[len(source_dir):]

        """ 
        print(f"[DEBUG] should_ignore->src_file_str is {src_file_str}")
        print(f"[DEBUG] should_ignore->compare_fname is {compare_fname}")
        print(f"[DEBUG] should_ignore->pattern is {pattern}")
        print(f"[DEBUG] should_ignore->clean_pattern is {clean_pattern}")
        print(f"[DEBUG] should_ignore->dirname is {dirname}")
        print(f"[DEBUG] should_ignore->endswith is {dirname.endswith(clean_pattern)}")
        """
       
        # Ignore if pattern is a parent directory set in ignore file list
        if dirname.endswith(clean_pattern) or dirname.endswith(clean_pattern + os.sep):
            return True

        # Compare the full path of the source file origin versus the actual string pattern
        if src_file_str == pattern:
            return True
        
        if compare_fname == pattern:
            return True

        if fnmatch.fnmatch(compare_fname, clean_pattern):
            return True 

    return False

def get_destination_path(source_path, source_root, dest_root):
    """
    Calculate destination path with index.md renaming logic.
    If file is index.md, rename it to {parent-directory}.md
    """
    # Get relative path from source root
    rel_path = os.path.relpath(source_path, source_root)
    
    """
    print(f"[DEBUG] get_destination_path->source_path is {source_path}")
    print(f"[DEBUG] get_destination_path->source_root is {source_root}")
    print(f"[DEBUG] get_destination_path->dest_root is {dest_root}")
    print(f"[DEBUG] get_destination_path->rel_path is {rel_path}")
    """
    
    # Check if it's an index.md file
    if os.path.basename(source_path) == 'index.md':
        # Get parent directory name
        parent_dir = os.path.basename(os.path.dirname(source_path))
        # Replace index.md with {parent-dir}.md
        rel_path = os.path.join(
            os.path.dirname(rel_path),
            f"{parent_dir}.md"
        )
    
    # Construct destination path
    dest_path = os.path.join(dest_root, rel_path)
    return dest_path


 
def copy_with_mode(source_path, dest_path, overwrite_mode='always'):
    """
    Copy file with different overwrite behaviors.
    
    Args:
        source_path: Source file path
        dest_path: Destination file path
        overwrite_mode: 'always', 'never', 'newer', 'ask'
    
    Returns:
        str: Status ('copied', 'skipped', 'overwritten')
    """
    exists = os.path.exists(dest_path)
    
    if overwrite_mode == 'never' and exists:
        print(f"[SKIPPED] {dest_path} (already exists)")
        return 'skipped'
    
    if overwrite_mode == 'newer' and exists:
        if os.path.getmtime(source_path) <= os.path.getmtime(dest_path):
            print(f"[SKIPPED] {dest_path} (up to date)")
            return 'skipped'
    
    if overwrite_mode == 'ask' and exists:
        while True:
            response = input(f"Overwrite '{dest_path}'? (y/n): ").lower().strip()

            if response in ('y', 'yes'):
                break  # Proceed to copy
            elif response in ('n', 'no'):
                print(f"[SKIPPED] {dest_path}")
                return 'skipped'
            else:
                print("⚠️  Invalid input. Please enter 'y' (yes) or 'n' (no).")
    
    # Copy the file
    shutil.copy2(source_path, dest_path)
    
    if exists:
        print(f"[OVERWRITTEN] {dest_path}")
        return 'overwritten'
    else:
        print(f"[COPIED] {dest_path}")
        return 'copied'
 


def copy_docs(source_dir, dest_dir, ignore_file='ignore_list.txt', overwrite_mode='always'):
    """
    Copy documentation files with custom rules.
    
    Args:
        source_dir: Source directory to copy from
        dest_dir: Destination directory to copy to
        ignore_file: File containing ignore patterns
    """
    # Load ignore patterns
    ignore_patterns = load_ignore_patterns(ignore_file)
    
    print(f"Source: {source_dir}")
    print(f"Destination: {dest_dir}")
    print(f"Ignore patterns loaded: {len(ignore_patterns)}")
    print("-" * 60)
    
    # Track statistics
    stats = {
        'copied': 0,
        'ignored': 0,
        'renamed': 0
    }
    
    # Walk through source directory
    for root, dirs, files in os.walk(source_dir):
        # Filter out ignored directories (modifies dirs in-place)
        dirs[:] = [d for d in dirs if not should_ignore(os.path.join(root, d), source_dir, ignore_patterns)]
        
        for file in files:
            source_path = os.path.join(root, file)
            
            #print(f"[DEBUG] Checking file : '{source_path}'")
            #print(f"[DEBUG] Ignore patterns: {ignore_patterns}")
            #print(f"[DEBUG] Should ignore  : {should_ignore(source_path, source_dir, ignore_patterns)}")
    
            # Check if file should be ignored
            if should_ignore(source_path, source_dir, ignore_patterns):
                print(f"[IGNORED] {source_path}")
                stats['ignored'] += 1
                continue
            
            # Get destination path (with index.md renaming)
            dest_path = get_destination_path(source_path, source_dir, dest_dir)
            
            # Create destination directory if it doesn't exist
            os.makedirs(os.path.dirname(dest_path), exist_ok=True)
            
            # Copy file
            #shutil.copy2(source_path, dest_path)
            copy_with_mode(source_path, dest_path, overwrite_mode)
            
            # Log action
            if file == 'index.md':
                print(f"[RENAMED] {source_path} → {dest_path}")
                stats['renamed'] += 1
            else:
                print(f"[COPIED]  {source_path} → {dest_path}")
                stats['copied'] += 1
    
    # Print summary
    print("-" * 60)
    print(f"Summary:")
    print(f"  Files copied: {stats['copied']}")
    print(f"  Files renamed (index.md): {stats['renamed']}")
    print(f"  Files/dirs ignored: {stats['ignored']}")
    print(f"  Total processed: {stats['copied'] + stats['renamed']}")


def main():
    """Main function."""

    parser = argparse.ArgumentParser(description='Copy documentation files')
    parser.add_argument('--overwrite',
                        choices=['always', 'never', 'newer', 'ask'],
                        default='always',
                        help='Overwrite behavior (default: always)')
    args = parser.parse_args()

    # Load configuration from file
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))
    config = load_config(f"{BASE_DIR}/../conf/config.ini")
    
    home = os.environ.get('HOME')
    SOURCE_DIR = config.get('cc_gen_pdf_paths', 'CC_MKDOCS_SOURCE_DIR', fallback=f"{home}/cc-manual-gen/mkdocs/cc-docs/docs/")
    DEST_DIR = config.get('cc_gen_pdf_paths', 'CC_SPHINX_SRC_DIR', fallback=f"{home}/cc-manual-gen/sphinx/src/")
    IGNORE_FILE = f"{BASE_DIR}/../conf/" + config.get('cc_gen_pdf_paths', 'CC_PDFGEN_IGNORE_FILE', fallback=f"{BASE_DIR}/../conf/ignore_file_list.txt")


    print(f"Config loaded! See allocated params:")
    print(f"  SOURCE_DIR: {SOURCE_DIR}")
    print(f"  DEST_DIR: {DEST_DIR}")
    print(f"  IGNORE_FILE: {IGNORE_FILE}")
    print("-" * 60)

    # Verify source directory exists
    if not os.path.exists(SOURCE_DIR):
        print(f"Error: Source directory '{SOURCE_DIR}' not found!")
        return
    
    # Run copy operation
    copy_docs(SOURCE_DIR, DEST_DIR, IGNORE_FILE, args.overwrite)


if __name__ == '__main__':
    main()

