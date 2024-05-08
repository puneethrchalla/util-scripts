
dict1 = {'a': 1, 'b': 2, 'c': 3}
dict2 = {'a': 1, 'b': 4, 'c': 3}

# Get the keys that are present in both dictionaries
common_keys = set(dict1.keys()) & set(dict2.keys())

# Filter out keys with same values
diff_keys = set(key for key in common_keys if dict1[key] != dict2[key])

print("Keys with different values:", diff_keys)