# Contributing to BashCoin

Thank you for your interest in contributing to BashCoin! This document provides guidelines for contributing to the project.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/your-username/bashcoin.git`
3. Create a feature branch: `git checkout -b feature/your-feature-name`
4. Make your changes
5. Test your changes thoroughly
6. Submit a pull request

## Development Setup

```bash
# Build the project
make build

# Start containers
make up

# Run tests
make test-multi
make test-failure
```

## Code Style

### Bash Scripts

- Use `#!/bin/bash` shebang
- Use `set -e` for error handling
- Add comments for complex logic
- Use meaningful variable names
- Follow existing code style

Example:
```bash
#!/bin/bash
set -e

# Description of what this script does
NODE_ID=${NODE_ID:-"node1"}
DATA_DIR="/data"

# Function description
function process_transaction() {
    local tx_file=$1
    # Implementation
}
```

### JSON/JSONL

- Use jq for JSON processing
- Pretty-print JSON with `jq .`
- One JSON object per line in JSONL files

## Testing

Before submitting a PR, ensure:

1. All existing functionality still works
2. Your changes don't break existing tests
3. New features have appropriate tests

```bash
# Basic test
make transaction
make balance

# Multi-transaction test
make test-multi

# Failure recovery test
make test-failure
```

## Areas for Contribution

### High Priority

1. **Automated Testing**: Add comprehensive test suite
2. **Byzantine Fault Tolerance**: Implement PBFT or similar
3. **Web Interface**: Create a web UI for node management
4. **REST API**: Add HTTP API for programmatic access
5. **Monitoring**: Add Prometheus/Grafana monitoring

### Medium Priority

1. **Performance Optimization**: Improve transaction throughput
2. **Incremental Sync**: Optimize rsync to only transfer new data
3. **Transaction Types**: Add support for different transaction types
4. **Multi-signature**: Implement multi-sig transactions
5. **Documentation**: Improve and expand documentation

### Low Priority

1. **CLI Tools**: Better command-line interface
2. **Configuration**: Make parameters configurable
3. **Logging**: Improve logging and debugging
4. **Metrics**: Add more metrics and statistics

## Pull Request Guidelines

1. **Title**: Use clear, descriptive titles
   - Good: "Add REST API for balance queries"
   - Bad: "Update files"

2. **Description**: Explain what and why
   ```markdown
   ## Changes
   - Added feature X
   - Fixed bug Y
   
   ## Motivation
   This change improves...
   
   ## Testing
   Tested by...
   ```

3. **Code Quality**:
   - Follow existing code style
   - Add comments for complex logic
   - Remove debug code
   - Update documentation if needed

4. **Commits**:
   - Use meaningful commit messages
   - Keep commits focused and atomic
   - Squash minor fixes before submitting

## Feature Requests

Have an idea? Open an issue with:

1. **Clear Title**: Describe the feature briefly
2. **Use Case**: Explain why this feature is useful
3. **Proposed Solution**: How you think it should work
4. **Alternatives**: Other approaches you considered

## Bug Reports

Found a bug? Open an issue with:

1. **Title**: Brief description of the bug
2. **Environment**: Docker version, OS, etc.
3. **Steps to Reproduce**: Exact steps to trigger the bug
4. **Expected Behavior**: What should happen
5. **Actual Behavior**: What actually happens
6. **Logs**: Relevant log output

Example:
```markdown
## Bug: Transaction not propagating to node3

**Environment:**
- Docker version: 20.10.8
- OS: Ubuntu 20.04
- BashCoin version: main branch

**Steps to Reproduce:**
1. Start all nodes with `make up`
2. Send transaction from node1 to node2
3. Check balance on node3 with `make balance`

**Expected:** Balance should update on all nodes
**Actual:** Balance not updated on node3

**Logs:**
```
[paste relevant logs]
```
```

## Development Workflow

1. **Create Issue**: Describe what you want to work on
2. **Get Feedback**: Wait for maintainer feedback
3. **Fork & Branch**: Create feature branch
4. **Develop**: Make your changes
5. **Test**: Thoroughly test your changes
6. **Document**: Update relevant documentation
7. **Submit PR**: Create pull request
8. **Address Feedback**: Make requested changes
9. **Merge**: Maintainer merges your PR

## Code Review Process

PRs are reviewed for:

1. **Functionality**: Does it work as intended?
2. **Code Quality**: Is the code clean and maintainable?
3. **Testing**: Are there adequate tests?
4. **Documentation**: Is it properly documented?
5. **Style**: Does it follow project conventions?

## Communication

- **Issues**: For bugs and feature requests
- **Pull Requests**: For code contributions
- **Discussions**: For questions and ideas

## License

By contributing, you agree that your contributions will be licensed under the Apache License, Version 2.0.

## Questions?

If you have questions about contributing, feel free to:
- Open an issue with the "question" label
- Check existing issues and pull requests
- Review the documentation in README.md

Thank you for contributing to BashCoin! 🚀

